// Xibo player Rust implementation, (c) 2022-2024 Georg Brandl.
// Licensed under the GNU AGPL, version 3 or later.

//! Schedule parsing and scheduling.

use std::{fs::File, path::Path};
use anyhow::{Context, Result};
use time::{OffsetDateTime, PrimitiveDateTime};
use elementtree::Element;
use serde::{Serialize, Deserialize};
use crate::resource::LayoutId;
use crate::util::{TIME_FMT, ElementExt};

/// A daypart: recurring schedule based on days of week and time ranges
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DayPart {
    layout_id: LayoutId,
    priority: i32,
    /// Days of week when this daypart is active (1=Monday, 7=Sunday)
    days_of_week: Vec<u8>,
    /// Start time as (hour, minute)
    start_time: (u8, u8),
    /// End time as (u8, u8)
    end_time: (u8, u8),
}

impl DayPart {
    /// Check if this daypart is active at the given date/time
    fn is_active_at(&self, dt: &OffsetDateTime) -> bool {
        let weekday = dt.weekday().number_from_monday();

        if !self.days_of_week.contains(&weekday) {
            return false;
        }

        let current_time = (dt.hour(), dt.minute());
        is_time_in_range(current_time, self.start_time, self.end_time)
    }

    fn priority(&self) -> i32 {
        self.priority
    }

    fn layouts(&self) -> Vec<LayoutId> {
        vec![self.layout_id]
    }
}

/// Parse time string in HH:MM format to (hour, minute) tuple
fn parse_time(time_str: &str) -> Result<(u8, u8)> {
    let parts: Vec<&str> = time_str.split(':').collect();
    if parts.len() != 2 {
        anyhow::bail!("Invalid time format: {}", time_str);
    }
    let hour: u8 = parts[0].parse().context("invalid hour")?;
    let minute: u8 = parts[1].parse().context("invalid minute")?;
    if hour > 23 || minute > 59 {
        anyhow::bail!("Time out of range: {}:{}", hour, minute);
    }
    Ok((hour, minute))
}

/// Check if a time falls within a time range, handling midnight crossing
fn is_time_in_range(time: (u8, u8), start: (u8, u8), end: (u8, u8)) -> bool {
    if start <= end {
        // Normal range: 09:00 - 17:00
        time >= start && time <= end
    } else {
        // Crosses midnight: 22:00 - 02:00
        time >= start || time <= end
    }
}

/// A campaign groups related layouts with shared priority and time window
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Campaign {
    id: i64,
    priority: i32,
    from: OffsetDateTime,
    to: OffsetDateTime,
    layouts: Vec<LayoutId>,
}

/// A standalone layout with its own priority and time window
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LayoutEntry {
    layout_id: LayoutId,
    priority: i32,
    from: OffsetDateTime,
    to: OffsetDateTime,
}

/// A schedule item can be either a campaign or a standalone layout
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ScheduleItem {
    Campaign(Campaign),
    StandaloneLayout(LayoutEntry),
}

impl ScheduleItem {
    /// Get the priority of this item (campaign or standalone layout)
    fn priority(&self) -> i32 {
        match self {
            ScheduleItem::Campaign(c) => c.priority,
            ScheduleItem::StandaloneLayout(l) => l.priority,
        }
    }

    /// Check if this item is currently active
    fn is_active(&self, now: OffsetDateTime) -> bool {
        match self {
            ScheduleItem::Campaign(c) => c.from <= now && now <= c.to,
            ScheduleItem::StandaloneLayout(l) => l.from <= now && now <= l.to,
        }
    }

    /// Get all layouts from this item (campaign returns multiple, standalone returns one)
    fn layouts(&self) -> Vec<LayoutId> {
        match self {
            ScheduleItem::Campaign(c) => c.layouts.clone(),
            ScheduleItem::StandaloneLayout(l) => vec![l.layout_id],
        }
    }
}

#[derive(Debug, Default, Serialize, Deserialize)]
pub struct Schedule {
    default: Option<LayoutId>,
    items: Vec<ScheduleItem>,
    dayparts: Vec<DayPart>,
}

impl Schedule {
    pub fn parse(tree: Element) -> Result<Self> {
        let tz_offset = OffsetDateTime::now_local().unwrap().offset();
        let mut items = Vec::new();

        // Parse campaigns (which contain multiple layouts)
        for campaign in tree.find_all("campaign") {
            let id = campaign.parse_attr("id")?;
            let prio = campaign.parse_attr("priority")?;
            let from = campaign.get_attr("fromdt").context("missing campaign fromdt")?;
            let to = campaign.get_attr("todt").context("missing campaign todt")?;
            let from = PrimitiveDateTime::parse(from, &TIME_FMT)
                .context("invalid campaign fromdt")?
                .assume_offset(tz_offset);
            let to = PrimitiveDateTime::parse(to, &TIME_FMT)
                .context("invalid campaign todt")?
                .assume_offset(tz_offset);

            // Parse layouts within this campaign
            let mut layouts = Vec::new();
            for layout in campaign.find_all("layout") {
                let layout_id = layout.parse_attr("file")?;
                layouts.push(layout_id);
            }

            if !layouts.is_empty() {
                items.push(ScheduleItem::Campaign(Campaign {
                    id,
                    priority: prio,
                    from,
                    to,
                    layouts,
                }));
            }
        }

        // Parse standalone layouts (direct children of <schedule>)
        // We iterate over direct children to avoid getting layouts inside campaigns
        for child in tree.children() {
            if child.tag().name() == "layout" {
                let id = child.parse_attr("file")?;
                let prio = child.parse_attr("priority")?;
                let from = child.get_attr("fromdt").context("missing layout fromdt")?;
                let to = child.get_attr("todt").context("missing layout todt")?;
                let from = PrimitiveDateTime::parse(from, &TIME_FMT)
                    .context("invalid layout fromdt")?
                    .assume_offset(tz_offset);
                let to = PrimitiveDateTime::parse(to, &TIME_FMT)
                    .context("invalid layout todt")?
                    .assume_offset(tz_offset);

                items.push(ScheduleItem::StandaloneLayout(LayoutEntry {
                    layout_id: id,
                    priority: prio,
                    from,
                    to,
                }));
            }
        }

        // Parse dayparts (recurring schedules based on days/times)
        let mut dayparts = Vec::new();
        for child in tree.children() {
            if child.tag().name() == "daypart" {
                let layout_id = child.parse_attr("file")?;
                let priority = child.parse_attr("priority").unwrap_or(0);

                // Parse days of week (comma-separated, 1=Monday to 7=Sunday)
                let days_str = child.get_attr("days").unwrap_or("1,2,3,4,5,6,7");
                let days_of_week: Vec<u8> = days_str
                    .split(',')
                    .filter_map(|s| s.trim().parse().ok())
                    .collect();

                // Parse start time (HH:MM format)
                let start_str = child.get_attr("startTime").unwrap_or("00:00");
                let start_time = parse_time(start_str)?;

                // Parse end time (HH:MM format)
                let end_str = child.get_attr("endTime").unwrap_or("23:59");
                let end_time = parse_time(end_str)?;

                dayparts.push(DayPart {
                    layout_id,
                    priority,
                    days_of_week,
                    start_time,
                    end_time,
                });
            }
        }

        let mut default = None;
        if let Some(def) = tree.find("default") {
            default = Some(def.parse_attr("file")?);
        }

        Ok(Self {
            default,
            items,
            dayparts,
        })
    }

    pub fn layouts_now(&self) -> Vec<LayoutId> {
        let now = OffsetDateTime::now_local().unwrap();

        // Filter to active dayparts
        let active_dayparts: Vec<&DayPart> = self.dayparts.iter()
            .filter(|dp| dp.is_active_at(&now))
            .collect();

        // Filter to active items (campaigns and standalone layouts)
        let active_items: Vec<&ScheduleItem> = self.items.iter()
            .filter(|item| item.is_active(now))
            .collect();

        // If no active dayparts or items, return default
        if active_dayparts.is_empty() && active_items.is_empty() {
            return if let Some(def) = self.default {
                vec![def]
            } else {
                Vec::new()
            };
        }

        // Find maximum priority across dayparts and items
        let max_daypart_priority = active_dayparts.iter()
            .map(|dp| dp.priority())
            .max()
            .unwrap_or(i32::MIN);

        let max_item_priority = active_items.iter()
            .map(|item| item.priority())
            .max()
            .unwrap_or(i32::MIN);

        let max_priority = max_daypart_priority.max(max_item_priority);

        // Collect all layouts from dayparts and items with max priority
        let mut layouts = Vec::new();

        for dp in active_dayparts {
            if dp.priority() == max_priority {
                layouts.extend(dp.layouts());
            }
        }

        for item in active_items {
            if item.priority() == max_priority {
                layouts.extend(item.layouts());
            }
        }

        layouts
    }

    pub fn from_file(path: impl AsRef<Path>) -> Result<Self> {
        serde_json::from_reader(File::open(path.as_ref())?)
            .context("deserializing schedule")
    }

    pub fn to_file(&self, path: impl AsRef<Path>) -> Result<()> {
        serde_json::to_writer_pretty(File::create(path.as_ref())?, self)
            .context("serializing schedule")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn create_test_schedule_xml(xml_content: &str) -> Element {
        Element::from_reader(&mut xml_content.as_bytes()).unwrap()
    }

    #[test]
    fn test_campaign_priority_beats_standalone() {
        // Campaign with priority 10 should beat standalone layout with priority 5
        let xml = r#"
            <schedule>
                <default file="0" />
                <layout file="100" priority="5" fromdt="2024-01-01 00:00:00" todt="2030-12-31 23:59:59" />
                <campaign id="1" priority="10" fromdt="2024-01-01 00:00:00" todt="2030-12-31 23:59:59">
                    <layout file="200" />
                    <layout file="201" />
                    <layout file="202" />
                </campaign>
            </schedule>
        "#;

        let tree = create_test_schedule_xml(xml);
        let schedule = Schedule::parse(tree).unwrap();
        let layouts = schedule.layouts_now();

        // Should return campaign layouts (priority 10) not standalone (priority 5)
        assert_eq!(layouts.len(), 3);
        assert!(layouts.contains(&200));
        assert!(layouts.contains(&201));
        assert!(layouts.contains(&202));
    }

    #[test]
    fn test_multiple_campaigns_same_priority() {
        // Multiple campaigns at same priority - all layouts should be included
        let xml = r#"
            <schedule>
                <default file="0" />
                <campaign id="1" priority="10" fromdt="2024-01-01 00:00:00" todt="2030-12-31 23:59:59">
                    <layout file="100" />
                    <layout file="101" />
                </campaign>
                <campaign id="2" priority="10" fromdt="2024-01-01 00:00:00" todt="2030-12-31 23:59:59">
                    <layout file="200" />
                    <layout file="201" />
                </campaign>
            </schedule>
        "#;

        let tree = create_test_schedule_xml(xml);
        let schedule = Schedule::parse(tree).unwrap();
        let layouts = schedule.layouts_now();

        // Both campaigns at priority 10, so all 4 layouts should be included
        assert_eq!(layouts.len(), 4);
        assert!(layouts.contains(&100));
        assert!(layouts.contains(&101));
        assert!(layouts.contains(&200));
        assert!(layouts.contains(&201));
    }

    #[test]
    fn test_campaign_out_of_time_window() {
        // Campaign outside time window should not be active
        let xml = r#"
            <schedule>
                <default file="0" />
                <layout file="100" priority="5" fromdt="2024-01-01 00:00:00" todt="2030-12-31 23:59:59" />
                <campaign id="1" priority="10" fromdt="2020-01-01 00:00:00" todt="2020-12-31 23:59:59">
                    <layout file="200" />
                    <layout file="201" />
                </campaign>
            </schedule>
        "#;

        let tree = create_test_schedule_xml(xml);
        let schedule = Schedule::parse(tree).unwrap();
        let layouts = schedule.layouts_now();

        // Campaign is expired, so standalone layout should win
        assert_eq!(layouts.len(), 1);
        assert_eq!(layouts[0], 100);
    }

    #[test]
    fn test_mixed_campaigns_and_standalone_same_priority() {
        // Mix of campaigns and standalone layouts at same priority
        let xml = r#"
            <schedule>
                <default file="0" />
                <layout file="100" priority="10" fromdt="2024-01-01 00:00:00" todt="2030-12-31 23:59:59" />
                <layout file="101" priority="10" fromdt="2024-01-01 00:00:00" todt="2030-12-31 23:59:59" />
                <campaign id="1" priority="10" fromdt="2024-01-01 00:00:00" todt="2030-12-31 23:59:59">
                    <layout file="200" />
                    <layout file="201" />
                </campaign>
            </schedule>
        "#;

        let tree = create_test_schedule_xml(xml);
        let schedule = Schedule::parse(tree).unwrap();
        let layouts = schedule.layouts_now();

        // All at priority 10, so all should be included
        assert_eq!(layouts.len(), 4);
        assert!(layouts.contains(&100));
        assert!(layouts.contains(&101));
        assert!(layouts.contains(&200));
        assert!(layouts.contains(&201));
    }

    #[test]
    fn test_no_active_schedules_returns_default() {
        // No active schedules should return default
        let xml = r#"
            <schedule>
                <default file="999" />
                <campaign id="1" priority="10" fromdt="2020-01-01 00:00:00" todt="2020-12-31 23:59:59">
                    <layout file="200" />
                </campaign>
            </schedule>
        "#;

        let tree = create_test_schedule_xml(xml);
        let schedule = Schedule::parse(tree).unwrap();
        let layouts = schedule.layouts_now();

        // Should return default layout
        assert_eq!(layouts.len(), 1);
        assert_eq!(layouts[0], 999);
    }

    #[test]
    fn test_campaign_layout_order_preserved() {
        // Campaign layouts should maintain their order
        let xml = r#"
            <schedule>
                <default file="0" />
                <campaign id="1" priority="10" fromdt="2024-01-01 00:00:00" todt="2030-12-31 23:59:59">
                    <layout file="205" />
                    <layout file="203" />
                    <layout file="204" />
                    <layout file="201" />
                    <layout file="202" />
                </campaign>
            </schedule>
        "#;

        let tree = create_test_schedule_xml(xml);
        let schedule = Schedule::parse(tree).unwrap();
        let layouts = schedule.layouts_now();

        // Campaign layouts should be in order
        assert_eq!(layouts.len(), 5);
        assert_eq!(layouts[0], 205);
        assert_eq!(layouts[1], 203);
        assert_eq!(layouts[2], 204);
        assert_eq!(layouts[3], 201);
        assert_eq!(layouts[4], 202);
    }

    #[test]
    fn test_backward_compatibility_no_campaigns() {
        // Old-style schedule without campaigns should still work
        let xml = r#"
            <schedule>
                <default file="0" />
                <layout file="100" priority="5" fromdt="2024-01-01 00:00:00" todt="2030-12-31 23:59:59" />
                <layout file="101" priority="10" fromdt="2024-01-01 00:00:00" todt="2030-12-31 23:59:59" />
                <layout file="102" priority="10" fromdt="2024-01-01 00:00:00" todt="2030-12-31 23:59:59" />
            </schedule>
        "#;

        let tree = create_test_schedule_xml(xml);
        let schedule = Schedule::parse(tree).unwrap();
        let layouts = schedule.layouts_now();

        // Highest priority layouts should be returned
        assert_eq!(layouts.len(), 2);
        assert!(layouts.contains(&101));
        assert!(layouts.contains(&102));
    }

    #[test]
    fn test_empty_campaign_ignored() {
        // Campaign with no layouts should be ignored
        let xml = r#"
            <schedule>
                <default file="0" />
                <layout file="100" priority="5" fromdt="2024-01-01 00:00:00" todt="2030-12-31 23:59:59" />
                <campaign id="1" priority="10" fromdt="2024-01-01 00:00:00" todt="2030-12-31 23:59:59">
                </campaign>
            </schedule>
        "#;

        let tree = create_test_schedule_xml(xml);
        let schedule = Schedule::parse(tree).unwrap();
        let layouts = schedule.layouts_now();

        // Empty campaign should be ignored, standalone layout wins
        assert_eq!(layouts.len(), 1);
        assert_eq!(layouts[0], 100);
    }

    #[test]
    fn test_serialization_deserialization() {
        // Test that schedule can be serialized and deserialized
        let xml = r#"
            <schedule>
                <default file="123" />
                <layout file="100" priority="5" fromdt="2024-01-01 00:00:00" todt="2030-12-31 23:59:59" />
                <campaign id="1" priority="10" fromdt="2024-01-01 00:00:00" todt="2030-12-31 23:59:59">
                    <layout file="200" />
                    <layout file="201" />
                </campaign>
            </schedule>
        "#;

        let tree = create_test_schedule_xml(xml);
        let schedule = Schedule::parse(tree).unwrap();

        // Serialize to JSON
        let json = serde_json::to_string(&schedule).unwrap();

        // Deserialize back
        let schedule2: Schedule = serde_json::from_str(&json).unwrap();

        // Should produce same layouts
        assert_eq!(schedule.layouts_now(), schedule2.layouts_now());
        assert_eq!(schedule.default, schedule2.default);
    }

    // Daypart tests

    #[test]
    fn test_parse_time() {
        assert_eq!(parse_time("09:30").unwrap(), (9, 30));
        assert_eq!(parse_time("00:00").unwrap(), (0, 0));
        assert_eq!(parse_time("23:59").unwrap(), (23, 59));
        assert!(parse_time("25:00").is_err());
        assert!(parse_time("12:60").is_err());
        assert!(parse_time("invalid").is_err());
    }

    #[test]
    fn test_is_time_in_range_normal() {
        // Normal range: 09:00 - 17:00
        assert!(is_time_in_range((9, 0), (9, 0), (17, 0)));
        assert!(is_time_in_range((12, 30), (9, 0), (17, 0)));
        assert!(is_time_in_range((17, 0), (9, 0), (17, 0)));
        assert!(!is_time_in_range((8, 59), (9, 0), (17, 0)));
        assert!(!is_time_in_range((17, 1), (9, 0), (17, 0)));
    }

    #[test]
    fn test_is_time_in_range_midnight_crossing() {
        // Crosses midnight: 22:00 - 02:00
        assert!(is_time_in_range((22, 0), (22, 0), (2, 0)));
        assert!(is_time_in_range((23, 30), (22, 0), (2, 0)));
        assert!(is_time_in_range((0, 0), (22, 0), (2, 0)));
        assert!(is_time_in_range((1, 30), (22, 0), (2, 0)));
        assert!(is_time_in_range((2, 0), (22, 0), (2, 0)));
        assert!(!is_time_in_range((21, 59), (22, 0), (2, 0)));
        assert!(!is_time_in_range((2, 1), (22, 0), (2, 0)));
        assert!(!is_time_in_range((12, 0), (22, 0), (2, 0)));
    }

    #[test]
    fn test_daypart_parsing() {
        let xml = r#"
            <schedule>
                <default file="0" />
                <daypart file="100" priority="10" days="1,2,3,4,5" startTime="09:00" endTime="17:00" />
            </schedule>
        "#;

        let tree = create_test_schedule_xml(xml);
        let schedule = Schedule::parse(tree).unwrap();

        assert_eq!(schedule.dayparts.len(), 1);
        assert_eq!(schedule.dayparts[0].layout_id, 100);
        assert_eq!(schedule.dayparts[0].priority, 10);
        assert_eq!(schedule.dayparts[0].days_of_week, vec![1, 2, 3, 4, 5]);
        assert_eq!(schedule.dayparts[0].start_time, (9, 0));
        assert_eq!(schedule.dayparts[0].end_time, (17, 0));
    }

    #[test]
    fn test_daypart_default_values() {
        let xml = r#"
            <schedule>
                <default file="0" />
                <daypart file="100" />
            </schedule>
        "#;

        let tree = create_test_schedule_xml(xml);
        let schedule = Schedule::parse(tree).unwrap();

        assert_eq!(schedule.dayparts.len(), 1);
        assert_eq!(schedule.dayparts[0].layout_id, 100);
        assert_eq!(schedule.dayparts[0].priority, 0);
        assert_eq!(schedule.dayparts[0].days_of_week, vec![1, 2, 3, 4, 5, 6, 7]);
        assert_eq!(schedule.dayparts[0].start_time, (0, 0));
        assert_eq!(schedule.dayparts[0].end_time, (23, 59));
    }

    #[test]
    fn test_daypart_beats_lower_priority_schedule() {
        // Test needs to run on a weekday during business hours to pass reliably
        // For CI/testing purposes, this is a structural test rather than time-dependent
        let xml = r#"
            <schedule>
                <default file="0" />
                <layout file="100" priority="5" fromdt="2024-01-01 00:00:00" todt="2030-12-31 23:59:59" />
                <daypart file="200" priority="10" days="1,2,3,4,5,6,7" startTime="00:00" endTime="23:59" />
            </schedule>
        "#;

        let tree = create_test_schedule_xml(xml);
        let schedule = Schedule::parse(tree).unwrap();

        // Daypart has priority 10 and is active all week, all day
        // Should beat the layout with priority 5
        let layouts = schedule.layouts_now();
        assert_eq!(layouts.len(), 1);
        assert_eq!(layouts[0], 200);
    }

    #[test]
    fn test_daypart_and_schedule_same_priority() {
        let xml = r#"
            <schedule>
                <default file="0" />
                <layout file="100" priority="10" fromdt="2024-01-01 00:00:00" todt="2030-12-31 23:59:59" />
                <daypart file="200" priority="10" days="1,2,3,4,5,6,7" startTime="00:00" endTime="23:59" />
            </schedule>
        "#;

        let tree = create_test_schedule_xml(xml);
        let schedule = Schedule::parse(tree).unwrap();

        // Both have priority 10, both should be included
        let layouts = schedule.layouts_now();
        assert_eq!(layouts.len(), 2);
        assert!(layouts.contains(&100));
        assert!(layouts.contains(&200));
    }

    #[test]
    fn test_multiple_dayparts() {
        let xml = r#"
            <schedule>
                <default file="0" />
                <daypart file="100" priority="10" days="1,2,3,4,5" startTime="00:00" endTime="23:59" />
                <daypart file="200" priority="10" days="6,7" startTime="00:00" endTime="23:59" />
            </schedule>
        "#;

        let tree = create_test_schedule_xml(xml);
        let schedule = Schedule::parse(tree).unwrap();

        assert_eq!(schedule.dayparts.len(), 2);

        // The result depends on the current day of the week
        // On weekdays (1-5): layout 100
        // On weekends (6-7): layout 200
        let layouts = schedule.layouts_now();
        assert_eq!(layouts.len(), 1);
        assert!(layouts[0] == 100 || layouts[0] == 200);
    }
}
