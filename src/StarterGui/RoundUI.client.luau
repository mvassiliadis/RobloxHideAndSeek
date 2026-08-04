--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(packages:WaitForChild("React"))
local ReactRoblox = require(packages:WaitForChild("ReactRoblox"))

local roundApp = require(script.Parent:WaitForChild("RoundApp"))
local reactRoot = script.Parent:WaitForChild("ReactRoot")

local root = ReactRoblox.createRoot(reactRoot)
root:render(React.createElement(roundApp))

script.Destroying:Connect(function()
	root:unmount()
end)
