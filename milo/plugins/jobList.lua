local Milo       = require('milo')
local Peripheral = require('peripheral')
local UI         = require('ui')

local colors     = _G.colors

local context = Milo:getContext()
local mon     = Peripheral.lookup(context.config.monitor) or
                error('Monitor is not attached')
local display = UI.Device {
  device = mon,
  textScale = .5,
}

local jobList = UI.Page {
  parent = display,
  grid = UI.Grid {
    sortColumn = 'displayName',
    backgroundFocusColor = colors.black,
    columns = {
      { heading = 'Qty',      key = 'count',       width = 6                      },
      { heading = 'Crafting', key = 'displayName', width = display.width / 2 - 10 },
      { heading = 'Status',   key = 'status',      width = display.width - 10     },
    },
  },
}

function jobList:showError(msg)
  self.grid:clear()
  self.grid:centeredWrite(math.ceil(self.grid.height / 2), msg)
  self:sync()
end

function jobList:updateList(craftList)
  if not Milo:isCraftingPaused() then
    self.grid:setValues(craftList)
    self.grid:update()
    self:draw()
    self:sync()
  end
end

function jobList.grid:getRowTextColor(row, selected)
  if row.statusCode == Milo.STATUS_ERROR then
    return colors.red
  elseif row.statusCode == Milo.STATUS_WARNING then
    return colors.yellow
  elseif row.statusCode == Milo.STATUS_INFO then
    return colors.lime
  end
  return UI.Grid:getRowTextColor(row, selected)
end

jobList:enable()
jobList:draw()
jobList:sync()

local JobListTask = {
  priority = 80,
}

function JobListTask:cycle()
  jobList:updateList(Milo:getCraftingStatus())
end

Milo:registerTask(JobListTask)
context.jobList = jobList
