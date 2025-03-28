-- settings.lua

data:extend({

    -- Map settings
    -- ============
    {
      name = "construction-approvals-indicator-size",
      setting_type = "runtime-global",
      type = "string-setting",
      default_value = "normal",
      allowed_values = {"tiny", "small", "normal", "large", "huge"},
    },

    -- Per-player settings
    -- ===================
    {
      setting_type = "runtime-per-user",
      name = "constructionPlanner-auto-approve",
      type = "bool-setting",
      default_value = true,
    },
})
