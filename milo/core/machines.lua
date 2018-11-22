local Config = require('config')
local Event  = require('event')
local itemDB = require('itemDB')
local Milo   = require('milo')
local sync   = require('sync')
local UI     = require('ui')
local Util   = require('util')

local colors = _G.colors
local device = _G.device
local turtle = _G.turtle

local context = Milo:getContext()

local nodeWizard

local function saveConfig()
	local t = { }
	for k,v  in pairs(context.config.nodes) do
		t[k] = v.adapter
		v.adapter = nil
	end

	Config.update('milo', context.config)

	for k,v  in pairs(t) do
		context.config.nodes[k].adapter = v
	end
	context.storage:initStorage()
end

local networkPage = UI.Page {
	titleBar = UI.TitleBar {
		previousPage = true,
		title = 'Network',
	},
	filter = UI.TextEntry {
		y = -2, x = 1, ex = -9,
		limit = 50,
		shadowText = 'filter',
		backgroundColor = colors.cyan,
		backgroundFocusColor = colors.cyan,
	},
	grid = UI.ScrollingGrid {
		y = 2, ey = -3,
		values = context.config.nodes,
		columns = {
			{                   key = 'suffix', 		width = 4, justify = 'right' },
			{ heading = 'Name', key = 'displayName' },
			{ heading = 'Type', key = 'mtype',      width = 4 },
			{ heading = 'Pri',  key = 'priority',   width = 3 },
		},
		sortColumn = 'displayName',
		help = 'Select Node',
	},
	remove = UI.Button {
		y = -2, x = -4,
		text = '-', event = 'remove_node',
		help = 'Remove Node',
	},
	statusBar = UI.StatusBar {
		ex = -9,
		backgroundColor = colors.lightGray,
	},
	storageStatus = UI.Text {
		x = -8, ex = -1, y = -1,
		backgroundColor = colors.lightGray,
	},
	notification = UI.Notification { },
	accelerators = {
		delete = 'remove_node',
	}
}

function networkPage.grid:getDisplayValues(row)
	row = Util.shallowCopy(row)
	local t = { row.name:match(':(.+)_(%d+)$') }
	if #t ~= 2 then
		t = { row.name:match('(.+)_(%d+)$') }
	end
	if t and #t == 2 then
		row.name, row.suffix = table.unpack(t)
		row.name = row.name .. '_' .. row.suffix
	end
	row.displayName = row.displayName or row.name
	return row
end

function networkPage.grid:getRowTextColor(row, selected)
	if not device[row.name] then
		return colors.red
	end
	if row.mtype == 'ignore' then
		return colors.lightGray
	end
	return UI.Grid:getRowTextColor(row, selected)
end

function networkPage:getList()
	for _, v in pairs(device) do
		if not context.config.nodes[v.name] then
			local node = {
				name  = v.name,
				mtype = 'ignore',
			}
			for _, page in pairs(nodeWizard.wizard.pages) do
				if page.isValidType and page:isValidType(node) then
					context.config.nodes[v.name] = node
					break
				end
			end
		end
	end
end

function networkPage:enable()
	local function updateStatus()
		local isOnline = context.storage:isOnline()
		self.storageStatus.value = isOnline and ' online' or 'offline'
		self.storageStatus.textColor = isOnline and colors.lime or colors.red
		self.storageStatus:draw()
	end

	self.handler = Event.on({ 'device_attach', 'device_detach', 'storage_online', 'storage_offline' }, function()
		self:getList()
		self:applyFilter()
		self.grid:draw()
		self.grid:sync()
		updateStatus()
		self:sync()
	end)

	self:getList()
	self:applyFilter()
	self:setFocus(self.filter)
	UI.Page.enable(self)
	updateStatus()
end

function networkPage:disable()
	UI.Page.disable(self)
	Event.off(self.handler)

	-- Since some storage may have been added/removed - force a full rescan
	context.storage:setDirty()
end

function networkPage:applyFilter()
	local t = Util.filter(context.config.nodes, function(v)
		return v.mtype ~= 'hidden'
	end)

	if #self.filter.value > 0 then
		local filter = self.filter.value:lower()
		t = Util.filter(t, function(v)
			return v.displayName and
					string.find(string.lower(v.displayName), filter, 1, true) or
					string.find(string.lower(v.name), filter, 1, true)
		end)
	end

	self.grid:setValues(t)
end

function networkPage:eventHandler(event)
	if event.type == 'grid_select' then
		if not device[event.selected.name] then
			self.notification:error('Unable to edit while disconnected')
		else
			UI:setPage('nodeWizard', event.selected)
		end

	elseif event.type == 'remove_node' then
		local node = self.grid:getSelected()
		if node then
			context.config.nodes[node.name] = nil
			saveConfig()
		end
		self:applyFilter()
		self.grid:draw()

	elseif event.type == 'text_change' then
		self:applyFilter()
		self.grid:draw()

	elseif event.type == 'grid_focus_row' then
		self.statusBar:setStatus(event.selected.name)

	elseif event.type == 'focus_change' then
		self.statusBar:setStatus(event.focused.help)

	else
		UI.Page.eventHandler(self, event)
	end
	return true
end

nodeWizard = UI.Page {
	titleBar = UI.TitleBar { title = 'Configure' },
	wizard = UI.Wizard {
		y = 2, ey = -2,
		pages = {
			general = UI.Window {
				index = 1,
				backgroundColor = colors.cyan,
				form = UI.Form {
					x = 2, ex = -2, y = 1, ey = 3,
					manualControls = true,
					[1] = UI.TextEntry {
						formLabel = 'Name', formKey = 'displayName',
						help = 'Set a friendly name',
						limit = 64, pruneEmpty = true,
					},
					[2] = UI.Chooser {
						width = 25,
						formLabel = 'Type', formKey = 'mtype',
						--nochoice = 'Storage',
						help = 'Select type',
					},
				},
				grid = UI.ScrollingGrid {
					y = 5, ey = -2, x = 2, ex = -2,
					columns = {
						{ heading = 'Slot', key = 'slot',        width = 4 },
						{ heading = 'Name', key = 'displayName',           },
						{ heading = 'Qty',  key = 'count'      , width = 3 },
					},
					sortColumn = 'slot',
					help = 'Contents of inventory',
				},
			},
			confirmation = UI.Window {
				title = 'Confirm changes',
				index = 2,
				notice = UI.TextArea {
					x = 2, ex = -2, y = 2, ey = -2,
					value =
[[Press accept to save the changes.

The settings will take effect immediately!]],
				},
			},
		},
	},
	statusBar = UI.StatusBar {
		backgroundColor = colors.cyan,
	},
	notification = UI.Notification { },
	filter = UI.SlideOut {
		backgroundColor = colors.cyan,
		menuBar = UI.MenuBar {
			buttons = {
				{ text = 'Save',    event = 'save'    },
				{ text = 'Cancel',  event = 'cancel'  },
			},
		},
		grid = UI.ScrollingGrid {
			x = 2, ex = -6, y = 2, ey = -6,
			columns = {
				{ heading = 'Name', key = 'displayName' },
			},
			sortColumn = 'displayName',
			accelerators = {
				delete = 'remove_entry',
			},
		},
		remove = UI.Button {
			x = -4, y = 4,
			text = '-', event = 'remove_entry', help = 'Remove',
		},
		form = UI.Form {
			x = 2, y = -4, height = 3,
			margin = 1,
			manualControls = true,
			[1] = UI.Checkbox {
				formLabel = 'Ignore Dmg', formKey = 'ignoreDamage',
				help = 'Ignore damage of item',
			},
			[2] = UI.Checkbox {
				formLabel = 'Ignore NBT', formKey = 'ignoreNbtHash',
				help = 'Ignore NBT of item',
			},
			[3] = UI.Chooser {
				width = 13,
				formLabel = 'Mode', formKey = 'blacklist',
				nochoice = 'whitelist',
				choices = {
					{ name = 'whitelist', value = false },
					{ name = 'blacklist', value = true },
				},
				help = 'Ignore damage of item'
			},
			scan = UI.Button {
				x = -11, y = 1,
				text = 'Scan', event = 'scan_turtle',
				help = 'Add items to turtle to add to filter',
			},
		},
		statusBar = UI.StatusBar {
			backgroundColor = colors.cyan,
		},
	},
}

--[[ Filter slide out ]] --
function nodeWizard.filter:show(entry, callback, whitelistOnly)
	self.entry = entry
	self.callback = callback

	if not self.entry.filter then
		self.entry.filter = { }
	end

	self.form:setValues(entry)
	self:resetGrid()

	self.form[3].inactive = whitelistOnly

	UI.SlideOut.show(self)
	self:setFocus(self.form.scan)

	Milo:pauseCrafting({ key = 'gridInUse', msg = 'Crafting paused' })
	sync.lock(turtle)
end

function nodeWizard.filter:hide()
	UI.SlideOut.hide(self)
	Milo:resumeCrafting({ key = 'gridInUse' })
	sync.release(turtle)
end

function nodeWizard.filter:resetGrid()
	local t = { }
	for k in pairs(self.entry.filter) do
		table.insert(t, itemDB:splitKey(k))
	end
	self.grid:setValues(t)
end

function nodeWizard.filter.grid:getDisplayValues(row)
	row = Util.shallowCopy(row)
	row.displayName = itemDB:getName(row)
	return row
end

function nodeWizard.filter:eventHandler(event)
	if event.type == 'focus_change' then
		self.statusBar:setStatus(event.focused.help)

	elseif event.type == 'scan_turtle' then
		local inventory = Milo:getTurtleInventory()
		for _,item in pairs(inventory) do
			self.entry.filter[Milo:uniqueKey(item)] = true
		end
		self:resetGrid()
		self.grid:update()
		self.grid:draw()
		turtle.emptyInventory()

	elseif event.type == 'remove_entry' then
		local row = self.grid:getSelected()
		if row then
			Util.removeByValue(self.grid.values, row)
			self.grid:update()
			self.grid:draw()
		end

	elseif event.type == 'save' then
		self.form:save()
		self.entry.filter = { }
		for _,v in pairs(self.grid.values) do
			self.entry.filter[Milo:uniqueKey(v)] = true
		end
		self:hide()
		self.callback()

	elseif event.type == 'cancel' then
		self:hide()

	else
		return UI.SlideOut.eventHandler(self, event)
	end
	return true
end

--[[ General Page ]] --
function nodeWizard.wizard.pages.general:enable()
	UI.Window.enable(self)
	self:focusFirst()
end

function nodeWizard.wizard.pages.general:showInventory(node)
	local inventory

	if device[node.name] and device[node.name].list then
		pcall(function()
			inventory = device[node.name].list()
			for k,v in pairs(inventory) do
				v.slot = k
			end
		end)
	end

	self.grid:setValues(inventory or { })
end

function nodeWizard.wizard.pages.general.grid:getDisplayValues(row)
	row = Util.shallowCopy(row)
	row.displayName = itemDB:getName(row)
	return row
end

function nodeWizard.wizard.pages.general:validate()
	if self.form:save() then
		for _, page in pairs(nodeWizard.wizard.pages) do
			page.index = nil
		end
		local index = 2
		nodeWizard.wizard.pages.general.index = 1
		nodeWizard.wizard.pages.confirmation.index = 2
		for _, page in pairs(nodeWizard.wizard.pages) do
			if not page.index then
				if not page.isValidFor or page:isValidFor(nodeWizard.node) then
					page.index = index
					index = index + 1
					if page.setNode then
						page:setNode(nodeWizard.node)
					end
				end
			end
		end
		nodeWizard.wizard.pages.confirmation.index = index
		return true
	end
end

--[[ Wizard ]] --
function nodeWizard:enable(node)
	local adapter = node.adapter
	node.adapter = nil	-- don't deep copy the adapter
	self.node = Util.deepCopy(node)
	self.node.adapter = adapter
	node.adapter = adapter

_G._p3 = self.node -- TODO: remove - debugging

	local choices = {
		{ name = 'Ignore', value = 'ignore', '' },
		{ name = 'Hidden', value = 'hidden', help = 'Do not show in list' },
	}
	for _, page in pairs(self.wizard.pages) do
		if page.isValidType then
			local choice = page:isValidType(self.node)
			if choice and not Util.find(choices, 'value', choice.value) then
				table.insert(choices, 2, choice)
			end
		end
	end
	self.wizard.pages.general.form[1].shadowText = self.node.name
	self.wizard.pages.general.form[2].choices = choices
	self.wizard.pages.general.form:setValues(self.node)

	self.wizard.pages.general:showInventory(self.node)

	-- restore indices
	for _, page in pairs(self.wizard.pages) do
		if not page.oindex then
			page.oindex = page.index
		end
		page.index = page.oindex
	end

	UI.Page.enable(self)
end

function nodeWizard:eventHandler(event)
	if event.type == 'cancel' then
		UI:setPreviousPage()

	elseif event.type == 'accept' then

		local adapter = self.node.adapter
		self.node.adapter = nil

		Util.prune(self.node, function(v)
			if type(v) == 'boolean' then
				return v
			elseif type(v) == 'string' then
				return #v > 0
			elseif type(v) == 'table' then
				return not Util.empty(v)
			end
			return true
		end)

		Util.clear(context.config.nodes[self.node.name])
		Util.merge(context.config.nodes[self.node.name], self.node)
		context.config.nodes[self.node.name].adapter = adapter

		saveConfig()

		UI:setPreviousPage()

	elseif event.type == 'choice_change' then
		local help
		if event.choice and event.choice.help then
			help = event.choice.help
		else
			help = ''
		end
		self.statusBar:setStatus(help)

	elseif event.type == 'edit_filter' then
		self.filter:show(event.entry, event.callback, event.whitelistOnly)

	elseif event.type == 'enable_view' then
		local current = event.next or event.prev
		self.titleBar.title = current.title or 'Node'
		self.titleBar:draw()

	elseif event.type == 'focus_change' then
		self.statusBar:setStatus(event.focused.help)

	elseif event.type  == 'form_invalid' or event.type == 'general_error' then
		self.notification:error(event.message)
		self:setFocus(event.field)

	else
		return UI.Page.eventHandler(self, event)
	end
	return true
end

UI:addPage('network', networkPage)
UI:addPage('nodeWizard', nodeWizard)
