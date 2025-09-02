local styles = data.raw["gui-style"]["default"]

styles.cf_filter_tabbed_scroll_pane = table.deepcopy(styles.deep_slots_scroll_pane)
styles.cf_filter_tabbed_scroll_pane.background_graphical_set.overall_tiling_horizontal_size = 63
styles.cf_filter_tabbed_scroll_pane.background_graphical_set.overall_tiling_vertical_size = 64

styles.cf_inside_deep_frame = table.deepcopy(styles.inside_deep_frame)
styles.cf_inside_deep_frame.background_graphical_set = {
    position = { 282, 17, },
    corner_size = 8,
    overall_tiling_horizontal_size = 63,
    overall_tiling_vertical_size = 64,
    overall_tiling_horizontal_padding = 4,
    overall_tiling_horizontal_spacing = 8,
    overall_tiling_vertical_padding = 4,
    overall_tiling_vertical_spacing = 8,
  }

styles.cf_filter_group_button_tab = {
  type = "button_style",
  parent = "filter_group_button_tab_slightly_larger",
  height = 72,
  width = 71,
  top_padding = 0,
  right_padding = 0,
  bottom_padding = 0,
  left_padding = -1,
  left_click_sound = "__core__/sound/gui-tab.ogg"
}

styles.cf_draggable_space_header = table.deepcopy(styles.draggable_space_header)
styles.cf_draggable_space_header.horizontally_stretchable = "on"
styles.cf_draggable_space_header.vertically_stretchable = "on"
styles.cf_draggable_space_header.right_margin = 4
styles.cf_draggable_space_header.height = 24

styles.cf_frame_title = table.deepcopy(styles.frame_title)
styles.cf_frame_title.horizontally_squashable = "on"
styles.cf_frame_title.vertically_stretchable = "on"
styles.cf_frame_title.bottom_padding = 3
styles.cf_frame_title.top_margin = -3

styles.cf_filter_frame = {
  type = "frame_style",
  parent = "filter_frame",
  horizontally_stretchable = "on",
  bottom_padding = 8,
  top_padding = 8,
  left_padding = 13,
  right_padding = 0,
 -- width = (40 * 10) + (13 * 2),
}

local table_utils = require "table_utils"
log(table_utils.table_to_string(styles.inside_deep_frame))

--[[
--deep_slots_scroll_pane
{
  ["type"] = "scroll_pane_style",
  ["parent"] = "deep_scroll_pane",
  ["minimal_height"] = 40,
  ["background_graphical_set"] = {
    ["position"] = {
      [1] = 282,
      [2] = 17,
    },
    ["corner_size"] = 8,
    ["overall_tiling_horizontal_size"] = 63,
    ["overall_tiling_vertical_size"] = 64,
    ["overall_tiling_horizontal_padding"] = 4,
    ["overall_tiling_horizontal_spacing"] = 8,
    ["overall_tiling_vertical_padding"] = 4,
    ["overall_tiling_vertical_spacing"] = 8,
  },
  ["vertical_flow_style"] = {
    ["type"] = "vertical_flow_style",
    ["parent"] = "packed_vertical_flow",
  },
}

--inside_deep_frame
{
  ["type"] = "frame_style",
  ["parent"] = "frame",
  ["padding"] = 0,
  ["graphical_set"] = {
    ["base"] = {
      ["position"] = {
        [1] = 17,
        [2] = 0,
      },
      ["corner_size"] = 8,
      ["center"] = {
        ["position"] = {
          [1] = 42,
          [2] = 8,
        },
        ["size"] = {
          [1] = 1,
          [2] = 1,
        },
      },
      ["draw_type"] = "outer",
    },
    ["shadow"] = {
      ["position"] = {
        [1] = 183,
        [2] = 128,
      },
      ["corner_size"] = 8,
      ["tint"] = {
        [1] = 0,
        [2] = 0,
        [3] = 0,
        [4] = 1,
      },
      ["scale"] = 0.5,
      ["draw_type"] = "inner",
    },
  },
  ["vertical_flow_style"] = {
    ["type"] = "vertical_flow_style",
    ["vertical_spacing"] = 0,
  },
}

]]