const std = @import("std");

var ad_map = std.StringArrayHashMap([]const u8).init(alloc);
    try ad_map.put("h1", "h1 { display: block; font-size: 2em; margin-top: 0.67em; margin-bottom: 0.67em; margin-left: 0px; margin-right: 0; }");
    try ad_map.put("h2", "h2 { display: block; font-size: 1.5em; }");
    try ad_map.put("h3", "h3 { display: block; font-size: 1.17em; }");
    try ad_map.put("h4", "h4 { display: block; font-size: 1em; }");
    try ad_map.put("h5", "h5 { display: block; font-size: 0.83em; }");
    try ad_map.put("h6", "h6 { display: block; font-size: 0.67em; }");