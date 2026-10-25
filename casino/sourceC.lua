-- =====================================================================
--  Developer : Sc00By
--  Platform  : Multi Theft Auto: San Andreas (MTA:SA)
--  File      : Sc00by - CASINO/casino/sourceC.lua
-- =====================================================================

local screenX, screenY = guiGetScreenSize()
local responsiveMultipler = 1

function respc(num)
	return math.ceil(num * responsiveMultipler)
end

function loadFonts()
	Roboto = dxCreateFont("files/fonts/Raleway.ttf", respc(12), false)
	Raleway14 = dxCreateFont("files/fonts/Raleway.ttf", respc(14), false)
	Raleway18 = dxCreateFont("files/fonts/Raleway.ttf", respc(18), false)
	Raleway24 = dxCreateFont("files/fonts/Raleway.ttf", respc(24), false)
	Raleway12 = dxCreateFont("files/fonts/Raleway.ttf", respc(12), false)
end

loadFonts()

addEventHandler("onAssetsLoaded", getRootElement(),
	function ()
		loadFonts()
	end
)

addEventHandler("onClientResourceStart", getResourceRootElement(),
	function ()
		setInteriorSoundsEnabled(false)

		-- Ensure models are restored to original before loading new ones
		engineRestoreModel(1979)
		engineRestoreModel(1853)
		engineRestoreModel(1854)
		engineRestoreModel(1855)
		engineRestoreModel(1856)
		engineRestoreModel(1857)
		engineRestoreModel(1895)
		engineRestoreModel(2188)
		engineRestoreModel(4334)
		engineRestoreModel(1859)
		engineRestoreModel(1860)

		-- Load new models and textures
		engineImportTXD(engineLoadTXD("files/kbroul2.txd"), 1979)
		engineImportTXD(engineLoadTXD("files/chips.txd"), 1853, 1854, 1855, 1856, 1857)
		engineImportTXD(engineLoadTXD("files/kb_wheel1.txd"), 1895)
		engineReplaceModel(engineLoadDFF("files/wheel_o_fortune.dff"), 1895)
		engineImportTXD(engineLoadTXD("files/kbblackjack.txd"), 2188)
		engineImportTXD(engineLoadTXD("files/pokertextura.txd"), 4334)
		engineReplaceCOL(engineLoadCOL("files/nagypoker.col"), 4334)
		engineReplaceModel(engineLoadDFF("files/nagypoker.dff"), 4334)
		engineImportTXD(engineLoadTXD("files/blinds.txd"), 1859, 1860)

		-- Optional: remove world objects if needed (won't affect custom replacements directly)
		removeWorldModel(2188, 10000, 0, 0, 0)
		removeWorldModel(1978, 10000, 0, 0, 0)
	end)

addEvent("chipSound", true)
addEventHandler("chipSound", getRootElement(),
	function (x, y, z, num)
		local soundEffect = playSound3D("files/chip" .. num .. ".mp3", x, y, z)

		setSoundMaxDistance(soundEffect, 25)
		setElementInterior(soundEffect, getElementInterior(localPlayer))
		setElementDimension(soundEffect, getElementDimension(localPlayer))
	end
)

local playerIcons = {}

addEventHandler("onClientElementDataChange", getRootElement(),
	function (dataName)
		if dataName == "playerIcons" then
			if source ~= localPlayer then
				if isElementStreamedIn(source) then
					local dataVal = getElementData(source, dataName)

					if dataVal then
						playerIcons[source] = {dataVal[1], formatNumberEx(dataVal[2], ","), getTickCount()}
					else
						playerIcons[source] = nil
					end
				end
			end
		end
	end)

addEventHandler("onClientRender", getRootElement(),
	function ()
		local now = getTickCount()
		local px, py, pz = getElementPosition(localPlayer)

		for player, data in pairs(playerIcons) do
			if not isElement(player) then
				playerIcons[player] = nil
			else
				local bx, by, bz = getPedBonePosition(player, 6)
				
				bz = bz + 0.75
				
				local x, y = getScreenFromWorldPosition(bx, by, bz)
				
				if x and y then
					local dist = getDistanceBetweenPoints3D(bx, by, bz, px, py, pz)
					
					if dist <= 25 then
						local scale = interpolateBetween(0.65, 0, 0, 0.15, 0, 0, dist / 100, "OutQuad")
						local r, g, b, a = 215, 89, 89, 200
						
						if data[1] == "plus" then
							r, g, b = 61, 122, 188
						end
						
						local progress = (now - data[3]) / 500

						if progress < 1 then
							a = a * progress
						elseif progress > 8 then
							a = 0
							playerIcons[player] = nil
						elseif progress >= 7 then
							a = a * (1 - (progress - 7))
						end
						
						local size = 128 * scale

						x = x - size / 2
						y = y - size / 2

						dxDrawImage(x, y, size, size, "files/" .. data[1] .. ".png", 0, 0, 0, tocolor(r, g, b, a))
						dxDrawText(data[2] .. " Coin", x, y + size, x + size, 0, tocolor(r, g, b, a), 1, Roboto, "center", "top")
					end
				end
			end
		end
	end)



function formatNumberEx(amount, stepper)
	amount = tonumber(amount)

	if not amount then
		return ""
	end

	local left, center, right = string.match(math.floor(amount), "^([^%d]*%d)(%d*)(.-)$")
	return left .. string.reverse(string.gsub(string.reverse(center), "(%d%d%d)", "%1" .. (stepper or " "))) .. right
end