-- =====================================================================
--  Developer : Sc00By
--  Platform  : Multi Theft Auto: San Andreas (MTA:SA)
--  File      : Sc00by - CASINO/casino/poker/sourceS.lua
-- =====================================================================

local databaseConnection = false

local pokerTableCols = {}
local pokerTablePeds = {}

local pokerDeckCards = {}
local pokerBoardPots = {}

local gameCheckTimers = {}
local nextRoundTimers = {}
local playerTimeoutTimers = {}

function execute(func, ...)
	local thread = coroutine.create(func)
	coroutine.resume(thread, ...)
end

function sleep(interval)
	local thread = coroutine.running()
	setTimer(
		function ()
			coroutine.resume(thread)
		end,
	interval, 1)
	coroutine.yield()
end

addEventHandler("onDatabaseConnected", root,
	function (connectionElement)
		databaseConnection = connectionElement
	end
)

addEventHandler("onResourceStart", resourceRoot,
	function ()
		databaseConnection = exports.mysql:getConn()

		if databaseConnection then
			dbQuery(
				function (queryHandle)
					local queryResult = dbPoll(queryHandle, 0)

					if queryResult then
						for rowIndex, rowInfo in ipairs(queryResult) do
							local currentSenTable = {
								tableId = rowInfo.id,
								posX = rowInfo.posX,
								posY = rowInfo.posY,
								posZ = rowInfo.posZ,
								rotZ = rowInfo.rotZ,
								interior = rowInfo.interior,
								dimension = rowInfo.dimension,
								smallBlind = rowInfo.smallBlind,
								bigBlind = rowInfo.bigBlind,
								minEntry = rowInfo.minEntry,
								maxEntry = rowInfo.maxEntry
							}
							createPokerTable(currentSenTable, true)
						end
					end
				end,
			databaseConnection, "SELECT * FROM pokertables")
		end
	end
)

addEventHandler("onResourceStop", resourceRoot,
	function ()
		for dataKey in pairs(getAllElementData(resourceRoot)) do
			removeElementData(resourceRoot, dataKey)
		end
	end
)

addEvent("requestPokerTables", true)
addEventHandler("requestPokerTables", resourceRoot,
	function ()
		if isElement(client) then
			triggerClientEvent(client, "requestPokerTables", resourceRoot, tablePositions)
		end
	end
)

addEvent("createPoker", true)
addEventHandler("createPoker", resourceRoot,
	function (dataTable)
		if isElement(client) then
			if type(dataTable) == "table" then
				local columnNames = {}
				local columnValues = {}

				for columnName, columnValue in pairs(dataTable) do
					table.insert(columnNames, columnName)
					table.insert(columnValues, columnValue)
				end

				dbQuery(
					function (queryHandle, sourcePlayer)
						local queryResult, numAffectedRows, lastInsertId = dbPoll(queryHandle, 0)

						if queryResult then
							lastInsertId = tonumber(lastInsertId)

							if lastInsertId then
								if isElement(sourcePlayer) then
									outputChatBox("#3d7abc[MTA]: #ffffffPoker table created successfully. #32b3ef(ID: " .. lastInsertId .. ")", sourcePlayer, 255, 255, 255, true)
								end

								if not dataTable.tableId then
									dataTable.tableId = lastInsertId
								end

								createPokerTable(dataTable, true)
							else
								if isElement(sourcePlayer) then
									outputChatBox("#d75959[MTA]: #ffffffPoker table creation failed.", sourcePlayer, 255, 255, 255, true)
								end
							end
						else
							if isElement(sourcePlayer) then
								outputChatBox("#d75959[MTA]: #ffffffPoker table creation failed.", sourcePlayer, 255, 255, 255, true)
							end
						end
					end,
				{client}, databaseConnection, "INSERT INTO pokertables (" .. table.concat(columnNames, ",") .. ") VALUES (" .. string.sub(string.rep("?,", #columnNames), 1, -2) .. ")", unpack(columnValues))
			end
		end
	end
)

function createPokerTable(tableInfo, justNowCreated)
	if tableInfo then
		local tableId = tableInfo.tableId or 0

		if tableId then
			tablePositions[tableId] = {
				tableInfo.posX,
				tableInfo.posY,
				tableInfo.posZ,
				tableInfo.rotZ,
				tableInfo.interior,
				tableInfo.dimension,
				tableInfo.smallBlind,
				tableInfo.bigBlind,
				tableInfo.minEntry,
				tableInfo.maxEntry
			}

			if not pokerDeckCards[tableId] then
				pokerDeckCards[tableId] = {}
			end

			if not pokerBoardPots[tableId] then
				pokerBoardPots[tableId] = {}
			end

			generateTables(tableId)

			-- Collision shape
			pokerTableCols[tableId] = createColSphere(tableInfo.posX, tableInfo.posY, tableInfo.posZ, 5)

			if isElement(pokerTableCols[tableId]) then
				setElementInterior(pokerTableCols[tableId], tableInfo.interior)
				setElementDimension(pokerTableCols[tableId], tableInfo.dimension)
				setElementData(pokerTableCols[tableId], "pokerTableId", tableId)
				setElementData(pokerTableCols[tableId], "occupiedSeats", {})
			end

			-- Osztó
			local theDealerPosition = realDealerPositions[tableId]

			pokerTablePeds[tableId] = createPed(189, theDealerPosition[1], theDealerPosition[2], theDealerPosition[3], theDealerPosition[4])

			if isElement(pokerTablePeds[tableId]) then
				setElementInterior(pokerTablePeds[tableId], tableInfo.interior)
				setElementDimension(pokerTablePeds[tableId], tableInfo.dimension)
				setElementFrozen(pokerTablePeds[tableId], true)
				setElementData(pokerTablePeds[tableId], "visibleName", "Dealer")
				setElementData(pokerTablePeds[tableId], "invulnerable", true)
			end

			-- Ha most lett lerakva az asztal, szinkronizáljuk
			if justNowCreated then
				triggerClientEvent("createPokerTable", resourceRoot, tableId, tablePositions[tableId])
			end
		end
	end
end

addCommandHandler("updatepoker",
	function (sourcePlayer, commandName, tableId, smallBlind, bigBlind, minEntry, maxEntry)
		if exports.integration:isPlayerAdmin(sourcePlayer) then
			tableId = tonumber(tableId)
			smallBlind = tonumber(smallBlind)
			bigBlind = tonumber(bigBlind)
			minEntry = tonumber(minEntry)
			maxEntry = tonumber(maxEntry)

			if not (tableId and smallBlind and bigBlind and minEntry and maxEntry) then
				outputChatBox("#3d7abc[Syntax]: #FFFFFF/" .. commandName .. " [ID] [Min. Bet] [Max. Bet] [Min. Required Bet] [Max. Required Bet]", sourcePlayer, 255, 255, 255, true)
			else
				local selectedPokerTable = tablePositions[tableId]

				if selectedPokerTable then
					local executionResult = dbExec(databaseConnection, "UPDATE pokertables SET smallBlind = ?, bigBlind = ?, minEntry = ?, maxEntry = ? WHERE tableId = ?", smallBlind, bigBlind, minEntry, maxEntry, tableId)

					if executionResult then
						outputChatBox("#3d7abc[MTA]: #ffffffPoker table modified successfully.", sourcePlayer, 255, 255, 255, true)

						selectedPokerTable[7] = smallBlind
						selectedPokerTable[8] = bigBlind
						selectedPokerTable[9] = minEntry
						selectedPokerTable[10] = maxEntry

						triggerClientEvent("updatePokerTable", resourceRoot, tableId, selectedPokerTable)
					end
				else
					outputChatBox("#d75959[MTA]: #ffffffThe selected poker table does not exist..", sourcePlayer, 255, 255, 255, true)
				end
			end
		end
	end
)

addCommandHandler("deletepoker",
	function (sourcePlayer, commandName, tableId)
		if exports.integration:isPlayerAdmin(sourcePlayer) then
			tableId = tonumber(tableId)

			if not tableId then
				outputChatBox("#3d7abc[Syntax]: #FFFFFF/" .. commandName .. " [ID]", sourcePlayer, 255, 255, 255, true)
			else
				if tablePositions[tableId] then
					local executionResult = dbExec(databaseConnection, "DELETE FROM pokertables WHERE tableId = ?", tableId)

					if executionResult then
						triggerClientEvent("deletePokerTable", resourceRoot, tableId)

						removePokerBoardData(tableId, "isGameIsOn")
						removePokerBoardData(tableId, "gameStage")
						removePokerBoardData(tableId, "boardCards")
						removePokerBoardData(tableId, "dealerSeat")
						removePokerBoardData(tableId, "smallBlind")
						removePokerBoardData(tableId, "bigBlind")
						removePokerBoardData(tableId, "lastPlayer")
						removePokerBoardData(tableId, "currentPlayer")
						removePokerBoardData(tableId, "currentCall")
						removePokerBoardData(tableId, "showdown")
						removePokerBoardData(tableId, "pot")

						for seatId = 1, maximumPlayers do
							local playerElement = getPokerSeatData(tableId, seatId, "element")

							if isElement(playerElement) then
								removeElementData(playerElement, "pokerTableId")
								removeElementData(playerElement, "pokerTableSeat")

								setElementFrozen(playerElement, false)
								setPedAnimation(playerElement, false)
							end

							removePokerSeatData(tableId, seatId, "element")
							removePokerSeatData(tableId, seatId, "pokerCoins")
							removePokerSeatData(tableId, seatId, "pokerCards")
							removePokerSeatData(tableId, seatId, "currentCall")
							removePokerSeatData(tableId, seatId, "roundCall")
							removePokerSeatData(tableId, seatId, "win")
						end

						if pokerTableCols[tableId] then
							if isElement(pokerTableCols[tableId]) then
								destroyElement(pokerTableCols[tableId])
							end

							pokerTableCols[tableId] = nil
						end

						if pokerTablePeds[tableId] then
							if isElement(pokerTablePeds[tableId]) then
								destroyElement(pokerTablePeds[tableId])
							end

							pokerTablePeds[tableId] = nil
						end

						if gameCheckTimers[tableId] then
							if isTimer(gameCheckTimers[tableId]) then
								killTimer(gameCheckTimers[tableId])
							end

							gameCheckTimers[tableId] = nil
						end

						if nextRoundTimers[tableId] then
							if isTimer(nextRoundTimers[tableId]) then
								killTimer(nextRoundTimers[tableId])
							end

							nextRoundTimers[tableId] = nil
						end

						if playerTimeoutTimers[tableId] then
							if isTimer(playerTimeoutTimers[tableId]) then
								killTimer(playerTimeoutTimers[tableId])
							end

							playerTimeoutTimers[tableId] = nil
						end

						tablePositions[tableId] = nil
						realGuiPositions[tableId] = nil
						realBlindPositions[tableId] = nil
						realCoinPositions[tableId] = nil
						realPedPositions[tableId] = nil
						realDealerPositions[tableId] = nil
						cardLinePositions[tableId] = nil
						realPlayerCardPositions[tableId] = nil

						pokerDeckCards[tableId] = nil
						pokerBoardPots[tableId] = nil

						outputChatBox("#3d7abc[MTA]: #ffffffPoker table successfully cleared. #32b3ef(" .. tableId .. ")", sourcePlayer, 255, 255, 255, true)
					end
				else
					outputChatBox("#d75959[MTA]: #ffffffThe selected poker table does not exist..", sourcePlayer, 255, 255, 255, true)
				end
			end
		end
	end
)

addEvent("joinPokerTable", true)
addEventHandler("joinPokerTable", resourceRoot,
	function (selectedTableId, selectedSeatId)
		if isElement(client) then
			if selectedTableId then
				if selectedSeatId then
					local pokerTable = tablePositions[selectedTableId]

					if pokerTable then
						local currentTableId = getElementData(client, "pokerTableId")

						if not currentTableId then
							local thePedPosition = realPedPositions[selectedTableId][selectedSeatId]

							if isElement(pokerTableCols[selectedTableId]) then
								local occupiedSeats = getElementData(pokerTableCols[selectedTableId], "occupiedSeats") or {}

								if occupiedSeats then
									table.insert(occupiedSeats, selectedSeatId)
								end

								setElementData(pokerTableCols[selectedTableId], "occupiedSeats", occupiedSeats)
							end

							setElementFrozen(client, true)
							setElementPosition(client, thePedPosition[1], thePedPosition[2], thePedPosition[3])
							setElementRotation(client, 0, 0, thePedPosition[4], "default", true)
							setPedAnimation(client, "FOOD", "FF_Sit_Look", -1, true, false, false)

							setElementData(client, "pokerTableSeat", selectedSeatId) 
							setElementData(client, "pokerTableId", selectedTableId)

							triggerClientEvent(client, "joinPokerTable", resourceRoot, selectedTableId)
						end
					end
				end
			end
		end
	end
)

addEvent("leavePokerTable", true)
addEventHandler("leavePokerTable", resourceRoot,
	function (selectedTableId)
		if isElement(client) then
			if selectedTableId then
				if tablePositions[selectedTableId] then
					local currentTableId = getElementData(client, "pokerTableId")

					if currentTableId == selectedTableId then
						local seatId = getElementData(client, "pokerTableSeat")

						if seatId then
							setPlayerLeave(selectedTableId, seatId)

							setElementData(client, "pokerTableId", false)
							setElementData(client, "pokerTableSeat", false)

							setElementFrozen(client, false)
							setPedAnimation(client, false)
						end
					end
				end
			end
		end
	end
)

addEventHandler("onPlayerQuit", root,
	function ()
		local pokerTableId = getElementData(source, "pokerTableId")

		if pokerTableId then
			local pokerTableSeat = getElementData(source, "pokerTableSeat")

			if pokerTableSeat then
				setPlayerLeave(pokerTableId, pokerTableSeat)
			end
		end
	end
)

addEvent("startPoker", true)
addEventHandler("startPoker", resourceRoot,
	function (buyInAmount)
		if isElement(client) then
			local pokerTableId = getElementData(client, "pokerTableId")

			if pokerTableId then
				local pokerTableSeat = getElementData(client, "pokerTableSeat")

				if pokerTableSeat then
					local pokerTable = tablePositions[pokerTableId]

					if pokerTable then
						buyInAmount = tonumber(buyInAmount)

						if buyInAmount then
							local currentCoins = exports.global:getMoney(client) or 0

							if currentCoins >= buyInAmount then
								local minimumBuyIn = pokerTable[9]
								local maximumBuyIn = pokerTable[10]

								if buyInAmount >= minimumBuyIn and buyInAmount <= maximumBuyIn then
									currentCoins = currentCoins - buyInAmount

									if currentCoins < 0 then
										currentCoins = 0
									end

									exports.global:setMoney(client, currentCoins)

									setPokerSeatData(pokerTableId, pokerTableSeat, "element", client)
									setPokerSeatData(pokerTableId, pokerTableSeat, "pokerCoins", buyInAmount)

									removePokerSeatData(pokerTableId, pokerTableSeat, "pokerCards")
									removePokerSeatData(pokerTableId, pokerTableSeat, "currentCall")
									removePokerSeatData(pokerTableId, pokerTableSeat, "roundCall")
									removePokerSeatData(pokerTableId, pokerTableSeat, "win")

									if not getPokerBoardData(pokerTableId, "isGameIsOn") then
										initializeRoundCheck(pokerTableId, false)
									end

									triggerClientEvent(client, "startPoker", resourceRoot, pokerTableId)
								else
									triggerClientEvent(client, "pokerChatMessage", resourceRoot, "#d75959The amount entered is invalid!")
								end
							else
								triggerClientEvent(client, "pokerChatMessage", resourceRoot, "#d75959The amount entered is invalid!")
							end
						end
					end
				end
			end
		end
	end
)

addEvent("pokerAction", true)
addEventHandler("pokerAction", resourceRoot,
	function (actionName, betAmount)
		if isElement(client) then
			if actionName then
				local pokerTableId = getElementData(client, "pokerTableId")

				if pokerTableId then
					local pokerTableSeat = getElementData(client, "pokerTableSeat")

					if pokerTableSeat then
						local currentPlayerSeat = getPokerBoardData(pokerTableId, "currentPlayer") or 0

						if currentPlayerSeat == pokerTableSeat then
							betAmount = tonumber(betAmount) or 0

							if actionName == "fold" then
								setPlayerFolded(pokerTableId, pokerTableSeat)
							else
								setPlayerBetted(pokerTableId, pokerTableSeat, betAmount)
							end
						else
							triggerClientEvent(client, "pokerChatMessage", resourceRoot, "#d75959Wait your turn, it's not your turn now.!")
						end
					end
				end
			end
		end
	end
)

function addPokerChatLine(textMessage, tableId)
	tableId = tonumber(tableId)

	if tableId then
		if type(textMessage) == "string" then
			local affectedPlayers = {}

			for seatId = 1, maximumPlayers do
				local playerElement = getPokerSeatData(tableId, seatId, "element")

				if isElement(playerElement) then
					table.insert(affectedPlayers, playerElement)
				end
			end

			if #affectedPlayers > 0 then
				triggerClientEvent(affectedPlayers, "pokerChatMessage", resourceRoot, textMessage)
			end
		end
	end
end

function setPlayerLeave(tableId, seatId, forcedLeave)
	local pokerTable = tablePositions[tableId]

	if pokerTable then
		local currentCall = getPokerSeatData(tableId, seatId, "currentCall") or 0

		if currentCall > 0 then
			local currentPotIndex = #pokerBoardPots[tableId]
			local currentPot = pokerBoardPots[tableId][currentPotIndex]

			if currentPot then
				currentPot.amount = currentPot.amount + currentCall
			end

			local potValue = 0

			for i = #pokerBoardPots[tableId], 1, -1 do
				local thisPot = pokerBoardPots[tableId][i]

				if thisPot then
					potValue = potValue + thisPot.amount
				end
			end

			setPokerBoardData(tableId, "pot", potValue)
		end

		for i = #pokerBoardPots[tableId], 1, -1 do
			local thisPot = pokerBoardPots[tableId][i]

			if thisPot then
				thisPot.contributors[seatId] = nil
			end
		end

		local remainingPlayers = 0

		for i = 1, maximumPlayers do
			if i ~= seatId then
				if isPokerSeatActive(tableId, i, false, true) then 
					remainingPlayers = remainingPlayers + 1
				end
			end
		end

		if remainingPlayers >= minimumPlayers then
			local pokerCards = getPokerSeatData(tableId, seatId, "pokerCards") or {}

			if #pokerCards > 0 then
				local lastPlayer = getPokerBoardData(tableId, "lastPlayer")
				local currentPlayer = getPokerBoardData(tableId, "currentPlayer")

				if currentPlayer == seatId then
					if currentPlayer ~= lastPlayer then
						actionToNextPlayer(tableId)
					end
				elseif lastPlayer == seatId then
					setPokerBoardData(tableId, "lastPlayer", findPreviousPlayer(tableId, lastPlayer))
				end
			end
		end

		local playerElement = getPokerSeatData(tableId, seatId, "element")

		if isElement(playerElement) then
			local chipsInPlay = getPokerSeatData(tableId, seatId, "pokerCoins") or 0

			if chipsInPlay > 0 then
				local slotCoins = exports.global:getMoney(playerElement) or 0

				slotCoins = slotCoins + chipsInPlay

				exports.global:setMoney(playerElement, slotCoins)
			end
		end

		local occupiedSeats = getElementData(pokerTableCols[tableId], "occupiedSeats") or {}

		removePokerSeatData(tableId, seatId, "element")
		removePokerSeatData(tableId, seatId, "pokerCoins")
		removePokerSeatData(tableId, seatId, "pokerCards")
		removePokerSeatData(tableId, seatId, "currentCall")
		removePokerSeatData(tableId, seatId, "roundCall")
		removePokerSeatData(tableId, seatId, "win")

		if occupiedSeats then
			local seatArrayIndex = false

			for i = 1, #occupiedSeats do
				if occupiedSeats[i] == seatId then
					seatArrayIndex = i
					break
				end
			end

			if seatArrayIndex then
				table.remove(occupiedSeats, seatArrayIndex)
			end

			setElementData(pokerTableCols[tableId], "occupiedSeats", occupiedSeats)
		end

		if #occupiedSeats < minimumPlayers then
			removePokerBoardData(tableId, "dealerSeat")
		end

		if isElement(playerElement) then
			if not forcedLeave then
				local playerName = exports.global:getPlayerName(playerElement)

				if playerName then
					addPokerChatLine("#3d7abc" .. playerName .. " #ffffffdropped out of the game!", tableId)
				end
			else
				setElementData(playerElement, "pokerTableId", false)
				setElementData(playerElement, "pokerTableSeat", false)

				setElementFrozen(playerElement, false)
				setPedAnimation(playerElement, false)

				outputChatBox("#d75959[MTA - Poker]: #ffffffYou have no more coins to continue..", playerElement, 255, 255, 255, true)
			end
		end

		if remainingPlayers < minimumPlayers then
			endRound(tableId)
		else
			local lastPlayer = getPokerBoardData(tableId, "lastPlayer")

			if lastPlayer == seatId then
				local currentPlayer = getPokerBoardData(tableId, "currentPlayer")

				if currentPlayer == seatId then
					execute(endPhase, tableId)
				end
			end
		end
	end
end

function setPlayerFolded(tableId, seatId, isTimeout)
	local pokerTable = tablePositions[tableId]

	if pokerTable then
		local currentPlayer = getPokerBoardData(tableId, "currentPlayer") or 0

		if currentPlayer == seatId then
			local pokerCards = getPokerSeatData(tableId, seatId, "pokerCards") or {}

			if #pokerCards > 0 then
				removePokerSeatData(tableId, seatId, "pokerCards")

				local playerElement = getPokerSeatData(tableId, seatId, "element")

				if isElement(playerElement) then
					local playerName = exports.global:getPlayerName(playerElement)

					if isTimeout then
						addPokerChatLine("#3d7abc[" .. playerName .. "]: #ffffffFold! (TimeOut)", tableId)
					else
						addPokerChatLine("#3d7abc[" .. playerName .. "]: #ffffffFold!", tableId)
					end
				end

				triggerClientEvent("playPokerSound", resourceRoot, tableId, "fold")

				for i = #pokerBoardPots[tableId], 1, -1 do
					local thisPot = pokerBoardPots[tableId][i]

					if thisPot then
						thisPot.contributors[seatId] = nil
					end
				end

				local remainingPlayers = 0

				for i = 1, maximumPlayers do
					if isPokerSeatActive(tableId, i, false, true) then 
						remainingPlayers = remainingPlayers + 1
					end
				end

				if remainingPlayers < minimumPlayers then
					local showdownActive = getPokerBoardData(tableId, "showdown")

					if not showdownActive then
						local winnerSeat = findNextPlayer(tableId, nil, false, true)

						if winnerSeat then
							resolveSidePots(tableId)
							givePotToWinner(tableId, winnerSeat)
						end

						endRound(tableId, true)
					end
				else
					local lastPlayer = getPokerBoardData(tableId, "lastPlayer")

					if lastPlayer == seatId then
						execute(endPhase, tableId)
					else
						actionToNextPlayer(tableId)
					end
				end
			end
		end
	end
end

function setPlayerBetted(tableId, seatId, betAmount)
	local pokerTable = tablePositions[tableId]

	if pokerTable then
		local currentPlayer = getPokerBoardData(tableId, "currentPlayer") or 0

		if currentPlayer == seatId then
			betAmount = tonumber(betAmount) or 0

			local playerElement = getPokerSeatData(tableId, seatId, "element")
			local playerCall = getPokerSeatData(tableId, seatId, "currentCall") or 0
			local playerCoins = getPokerSeatData(tableId, seatId, "pokerCoins") or 0

			local highestCall = getPokerBoardData(tableId, "currentCall") or 0
			local amountToCall = highestCall - playerCall

			if betAmount > amountToCall then
				if isElement(playerElement) then
					local playerName = exports.global:getPlayerName(playerElement)

					takePlayerPokerCoins(tableId, seatId, betAmount + amountToCall)

					if playerName then
						if betAmount > playerCoins then
							if highestCall == 0 then
								addPokerChatLine("#3d7abc[" .. playerName .. "]: #ffffffBet! (All-In)", tableId)
							else
								addPokerChatLine("#3d7abc[" .. playerName .. "]: #ffffffRaise! (All-In)", tableId)
							end
						elseif highestCall == 0 then
							addPokerChatLine("#3d7abc[" .. playerName .. "]: #ffffffBet! (" .. thousandsStepper(betAmount) .. " Coin)", tableId)
						else
							addPokerChatLine("#3d7abc[" .. playerName .. "]: #ffffffRaise! (" .. thousandsStepper(betAmount) .. " Coin)", tableId)
						end
					end

					triggerClientEvent("playPokerSound", resourceRoot, tableId, "raise")
				end

				local previousPlayer = findPreviousPlayer(tableId)

				if previousPlayer == currentPlayer then
					execute(endPhase, tableId)
				else
					setPokerBoardData(tableId, "lastPlayer", previousPlayer)
					actionToNextPlayer(tableId)
				end
			else
				if isElement(playerElement) then
					local playerName = exports.global:getPlayerName(playerElement)

					if amountToCall == 0 then
						if playerName then
							addPokerChatLine("#3d7abc[" .. playerName .. "]: #ffffffCheck!", tableId)
						end

						triggerClientEvent("playPokerSound", resourceRoot, tableId, "check")
					else
						takePlayerPokerCoins(tableId, seatId, amountToCall)

						if playerName then
							if amountToCall > playerCoins then
								addPokerChatLine("#3d7abc[" .. playerName .. "]: #ffffffCall! (All-In)", tableId)
							else
								addPokerChatLine("#3d7abc[" .. playerName .. "]: #ffffffCall!", tableId)
							end
						end

						triggerClientEvent("playPokerSound", resourceRoot, tableId, "call")
					end
				end

				local lastPlayer = getPokerBoardData(tableId, "lastPlayer")

				if lastPlayer == currentPlayer then
					execute(endPhase, tableId)
				else
					actionToNextPlayer(tableId)
				end
			end
		end
	end
end

function takePlayerPokerCoins(tableId, seatId, coinsAmount)
	if tableId then
		coinsAmount = tonumber(coinsAmount)

		if coinsAmount then
			coinsAmount = math.floor(math.abs(coinsAmount))

			if coinsAmount > 0 then
				local playerCoins = getPokerSeatData(tableId, seatId, "pokerCoins") or 0

				if playerCoins > 0 then
					local currentCall = getPokerSeatData(tableId, seatId, "currentCall") or 0
					local highestCall = getPokerBoardData(tableId, "currentCall") or 0

					if coinsAmount > playerCoins then
						coinsAmount = playerCoins
					end

					playerCoins = playerCoins - coinsAmount
					currentCall = currentCall + coinsAmount

					setPokerSeatData(tableId, seatId, "pokerCoins", playerCoins)
					setPokerSeatData(tableId, seatId, "currentCall", currentCall)
					setPokerSeatData(tableId, seatId, "roundCall", currentCall)

					if currentCall > highestCall then
						setPokerBoardData(tableId, "currentCall", currentCall)
					end
				end
			end
		end
	end
end

function isPokerSeatActive(tableId, seatId, skipCards, skipCoins)
	if tableId then
		if seatId then
			local playerElement = getPokerSeatData(tableId, seatId, "element")

			if isElement(playerElement) then
				local haveCoins = false
				local haveCards = false

				if not skipCoins then
					local pokerCoins = getPokerSeatData(tableId, seatId, "pokerCoins") or 0

					if pokerCoins > 0 then
						haveCoins = true
					end
				end

				if not skipCards then
					local pokerCards = getPokerSeatData(tableId, seatId, "pokerCards") or {}

					if #pokerCards > 0 then
						haveCards = true
					end
				end

				return (haveCards or skipCards) and (haveCoins or skipCoins)
			end
		end
	end
end

function findNextPlayer(tableId, startOffset, skipCards, skipCoins)
	if tableId then
		startOffset = tonumber(startOffset)

		if not startOffset then
			startOffset = getPokerBoardData(tableId, "currentPlayer") or 0
		end

		if startOffset ~= maximumPlayers then
			for i = startOffset + 1, maximumPlayers do
				if isPokerSeatActive(tableId, i, skipCards, skipCoins) then
					return i
				end
			end
		end

		for i = 1, startOffset do
			if isPokerSeatActive(tableId, i, skipCards, skipCoins) then
				return i
			end
		end
	end

	return nil
end

function findPreviousPlayer(tableId, startOffset, skipCards, skipCoins)
	if tableId then
		startOffset = tonumber(startOffset)

		if not startOffset then
			startOffset = getPokerBoardData(tableId, "currentPlayer") or 0
		end

		if startOffset ~= 0 then
			for i = startOffset - 1, 1, -1 do
				if isPokerSeatActive(tableId, i, skipCards, skipCoins) then
					return i
				end
			end
		end

		for i = maximumPlayers, startOffset, -1 do
			if isPokerSeatActive(tableId, i, skipCards, skipCoins) then
				return i
			end
		end
	end

	return nil
end

function initializeRoundCheck(tableId, changeDealer)
	local pokerTable = tablePositions[tableId]

	if pokerTable then
		if not isTimer(gameCheckTimers[tableId]) then
			gameCheckTimers[tableId] = setTimer(
				function ()
					startRound(tableId, changeDealer)
				end,
			5000, 1)
		end
	end
end

function startRound(tableId, changeDealer)
	local pokerTable = tablePositions[tableId]

	if pokerTable then
		if changeDealer == nil then
			changeDealer = true
		end

		if not getPokerBoardData(tableId, "isGameIsOn") then
			local sittingInCounter = 0

			for i = 1, maximumPlayers do
				local playerElement = getPokerSeatData(tableId, i, "element")

				if isElement(playerElement) then
					local chipsInPlay = getPokerSeatData(tableId, i, "pokerCoins") or 0

					if chipsInPlay > 0 then
						sittingInCounter = sittingInCounter + 1

						setPokerSeatData(tableId, i, "pokerCards", {})
						setPokerSeatData(tableId, i, "currentCall", 0)
						setPokerSeatData(tableId, i, "roundCall", 0)
					else
						setPlayerLeave(tableId, i, true)
					end
				end
			end

			if sittingInCounter >= minimumPlayers then
				setPokerBoardData(tableId, "isGameIsOn", true)
				setPokerBoardData(tableId, "currentCall", 0)
				setPokerBoardData(tableId, "pot", 0)

				pokerBoardPots[tableId] = {}

				if not pokerBoardPots[tableId][1] then
					pokerBoardPots[tableId][1] = {
						amount = 0,
						contributors = {}
					}
				end

				pokerDeckCards[tableId] = {}

				for i = 1, #cardRanks do
					for j = 1, #cardSuits do
						table.insert(pokerDeckCards[tableId], {i, j})
					end
				end

				table.shuffle(pokerDeckCards[tableId])

				local dealerSeat = getPokerBoardData(tableId, "dealerSeat")

				if not dealerSeat then
					local sittingInPlayers = {}

					for i = 1, maximumPlayers do
						if isPokerSeatActive(tableId, i, true, false) then
							table.insert(sittingInPlayers, i)
						end
					end

					dealerSeat = sittingInPlayers[math.random(#sittingInPlayers)]
				else
					local playerElement = getPokerSeatData(tableId, dealerSeat, "element")

					if not isElement(playerElement) then
						changeDealer = true
					end

					if changeDealer then
						dealerSeat = findNextPlayer(tableId, dealerSeat, true) 
					end
				end

				setPokerBoardData(tableId, "dealerSeat", dealerSeat)

				local smallBlindSeat = false
				local bigBlindSeat = false

				if sittingInCounter == 2 then
					smallBlindSeat = dealerSeat
				else
					smallBlindSeat = findNextPlayer(tableId, dealerSeat, true)
				end

				bigBlindSeat = findNextPlayer(tableId, smallBlindSeat, true) 

				setPokerBoardData(tableId, "smallBlind", smallBlindSeat)
				setPokerBoardData(tableId, "bigBlind", bigBlindSeat)

				takePlayerPokerCoins(tableId, smallBlindSeat, tablePositions[tableId][7])
				takePlayerPokerCoins(tableId, bigBlindSeat, tablePositions[tableId][8])	

				if isElement(pokerTablePeds[tableId]) then
					setPedAnimation(pokerTablePeds[tableId], "CASINO", "DEALONE", 800, false, false, false, false)
					setTimer(
						function ()
							if isElement(pokerTablePeds[tableId]) then
								setPedAnimation(pokerTablePeds[tableId], "CASINO", "DEALONE", 800, false, false, false, false)
							end
						end,
					800, sittingInCounter)
				end

				for i = 1, maximumPlayers do
					if isPokerSeatActive(tableId, i, true, false) then
						setPokerSeatData(tableId, i, "pokerCards", {
							table.remove(pokerDeckCards[tableId]),
							table.remove(pokerDeckCards[tableId])
						})
					end
				end

				setPokerBoardData(tableId, "lastPlayer", bigBlindSeat)
				actionToNextPlayer(tableId, true)
			end
		end
	end
end

function endRound(tableId)
	local pokerTable = tablePositions[tableId]

	if pokerTable then
		if playerTimeoutTimers[tableId] then
			if isTimer(playerTimeoutTimers[tableId]) then
				killTimer(playerTimeoutTimers[tableId])
			end

			playerTimeoutTimers[tableId] = nil
		end

		removePokerBoardData(tableId, "currentPlayer")

		resolveSidePots(tableId)

		local showdownActive = getPokerBoardData(tableId, "showdown")

		if not showdownActive then
			local mainPot = pokerBoardPots[tableId][1]

			if mainPot then
				if mainPot.amount > 0 then
					local winnerSeat = findNextPlayer(tableId, 0, false, true)

					if winnerSeat then
						givePotToWinner(tableId, winnerSeat)
					end
				end
			end
		end

		prepareNextRound(tableId)
	end
end

function prepareNextRound(tableId, alreadyWaited)
	local pokerTable = tablePositions[tableId]

	if pokerTable then
		local remainingPlayers = 0

		for i = 1, maximumPlayers do
			local playerElement = getPokerSeatData(tableId, i, "element")

			if isElement(playerElement) then
				local chipsInPlay = getPokerSeatData(tableId, i, "pokerCoins") or 0

				if chipsInPlay == 0 then
					setPlayerLeave(tableId, i, true)
				else
					remainingPlayers = remainingPlayers + 1
				end
			end
		end

		if playerTimeoutTimers[tableId] then
			if isTimer(playerTimeoutTimers[tableId]) then
				killTimer(playerTimeoutTimers[tableId])
			end

			playerTimeoutTimers[tableId] = nil
		end

		if nextRoundTimers[tableId] then
			if isTimer(nextRoundTimers[tableId]) then
				killTimer(nextRoundTimers[tableId])
			end

			nextRoundTimers[tableId] = nil
		end

		removePokerBoardData(tableId, "currentPlayer")

		if remainingPlayers < minimumPlayers then
			removePokerBoardData(tableId, "gameStage")
			removePokerBoardData(tableId, "boardCards")
			removePokerBoardData(tableId, "smallBlind")
			removePokerBoardData(tableId, "bigBlind")
			removePokerBoardData(tableId, "currentCall")
			removePokerBoardData(tableId, "showdown")
			removePokerBoardData(tableId, "pot")

			for i = 1, maximumPlayers do
				removePokerSeatData(tableId, i, "pokerCards")
				removePokerSeatData(tableId, i, "currentCall")
				removePokerSeatData(tableId, i, "roundCall")
				removePokerSeatData(tableId, i, "win")
			end

			setPokerBoardData(tableId, "lastPlayer", nil)
			setPokerBoardData(tableId, "dealerSeat", nil)
			setPokerBoardData(tableId, "isGameIsOn", false)
		else
			nextRoundTimers[tableId] = setTimer(
				function ()
					triggerClientEvent("playPokerSound", resourceRoot, tableId, "cardshuff")

					removePokerBoardData(tableId, "gameStage")
					removePokerBoardData(tableId, "boardCards")
					removePokerBoardData(tableId, "smallBlind")
					removePokerBoardData(tableId, "bigBlind")
					removePokerBoardData(tableId, "currentCall")
					removePokerBoardData(tableId, "showdown")
					removePokerBoardData(tableId, "pot")

					for i = 1, maximumPlayers do
						removePokerSeatData(tableId, i, "pokerCards")
						removePokerSeatData(tableId, i, "currentCall")
						removePokerSeatData(tableId, i, "roundCall")
						removePokerSeatData(tableId, i, "win")
					end

					nextRoundTimers[tableId] = setTimer(
						function ()
							setPokerBoardData(tableId, "isGameIsOn", false)
							initializeRoundCheck(tableId, true)
						end,
					8000, 1)
				end,
			alreadyWaited and 100 or 5000, 1)
		end
	end
end

function resolveSidePots(tableId)
	local pokerTable = tablePositions[tableId]

	if pokerTable then
		local currentPotId = #pokerBoardPots[tableId]
		local currentPot = pokerBoardPots[tableId][currentPotId]

		if not currentPot then
			return
		end

		local smallestBet = 0
		local allBetsAreEqual = true
		local contributorsCounter = 0

		for i = 1, maximumPlayers do
			local playerElement = getPokerSeatData(tableId, i, "element")

			if isElement(playerElement) then
				local currentBet = getPokerSeatData(tableId, i, "currentCall") or 0

				if currentBet > 0 then
					contributorsCounter = contributorsCounter + 1

					if smallestBet == 0 then
						smallestBet = currentBet
					elseif currentBet ~= smallestBet then
						allBetsAreEqual = false

						if currentBet < smallestBet then
							smallestBet = currentBet
						end
					end
				end
			end
		end

		local previousContributorsCounter = 0

		for seatId in pairs(currentPot.contributors) do
			local playerElement = getPokerSeatData(tableId, seatId, "element")

			if isElement(playerElement) then
				previousContributorsCounter = previousContributorsCounter + 1
			end
		end

		if contributorsCounter > 0 and contributorsCounter < previousContributorsCounter then
			table.insert(pokerBoardPots[tableId], {
				amount = 0,
				contributors = {}
			})
			currentPotId = currentPotId + 1
			currentPot = pokerBoardPots[tableId][currentPotId]
		end

		if allBetsAreEqual then
			for i = 1, maximumPlayers do
				local playerElement = getPokerSeatData(tableId, i, "element")

				if isElement(playerElement) then
					local currentBet = getPokerSeatData(tableId, i, "currentCall") or 0

					if currentBet > 0 then
						local playerCards = getPokerSeatData(tableId, i, "pokerCards") or {}

						if #playerCards > 0 then
							currentPot.contributors[i] = true
						end

						currentPot.amount = currentPot.amount + currentBet
					end
				end

				removePokerSeatData(tableId, i, "roundCall")
				removePokerSeatData(tableId, i, "currentCall")
			end

			local potValue = 0

			for i = #pokerBoardPots[tableId], 1, -1 do
				local thisPot = pokerBoardPots[tableId][i]

				if thisPot then
					potValue = potValue + thisPot.amount
				end
			end

			setPokerBoardData(tableId, "pot", potValue)
		else

			for i = 1, maximumPlayers do
				local playerElement = getPokerSeatData(tableId, i, "element")

				if isElement(playerElement) then
					local currentBet = getPokerSeatData(tableId, i, "currentCall") or 0

					if currentBet > 0 then
						local playerCards = getPokerSeatData(tableId, i, "pokerCards") or {}

						if #playerCards > 0 then
							currentPot.contributors[i] = true
						end

						if currentBet <= smallestBet then
							currentPot.amount = currentPot.amount + currentBet
							currentBet = 0
						else
							currentPot.amount = currentPot.amount + smallestBet
							currentBet = currentBet - smallestBet
						end

						removePokerSeatData(tableId, i, "roundCall")

						if currentBet > 0 then
							setPokerSeatData(tableId, i, "currentCall", currentBet, false) 
						else
							removePokerSeatData(tableId, i, "currentCall")
						end
					end
				end
			end

			table.insert(pokerBoardPots[tableId], {
				amount = 0,
				contributors = {}
			})

			resolveSidePots(tableId)
		end
	end
end

function actionToNextPlayer(tableId, isFirstAction)
	local pokerTable = tablePositions[tableId]

	if pokerTable then
		if playerTimeoutTimers[tableId] then
			if isTimer(playerTimeoutTimers[tableId]) then
				killTimer(playerTimeoutTimers[tableId])
			end

			playerTimeoutTimers[tableId] = nil
		end

		local oldActiveSeat = getPokerBoardData(tableId, "currentPlayer")

		if isFirstAction then
			oldActiveSeat = getPokerBoardData(tableId, "bigBlind")
		end

		local activeSeat = findNextPlayer(tableId, oldActiveSeat)
		local isPhaseEnd = false

		if not activeSeat then
			activeSeat = oldActiveSeat
			isPhaseEnd = true
		else
			local lastPlayerSeat = getPokerBoardData(tableId, "lastPlayer")

			if lastPlayerSeat then
				if not oldActiveSeat then
					isPhaseEnd = true
				elseif oldActiveSeat == activeSeat then
					isPhaseEnd = true
				elseif oldActiveSeat < lastPlayerSeat and lastPlayerSeat < activeSeat then
					isPhaseEnd = true
				elseif activeSeat < oldActiveSeat and oldActiveSeat < lastPlayerSeat then
					isPhaseEnd = true
				elseif lastPlayerSeat < activeSeat and activeSeat < oldActiveSeat then
					isPhaseEnd = true
				end
			end
		end

		if isPhaseEnd then
			execute(endPhase, tableId)
		else
			setPokerBoardData(tableId, "currentPlayer", activeSeat)

			if isFirstAction then
				local activePlayer = getPokerSeatData(tableId, activeSeat, "element")
				local otherPlayers = {}

				for playerIndex, playerElement in pairs(getElementsByType("player")) do
					if playerElement ~= activePlayer then
						table.insert(otherPlayers, playerElement)
					end
				end

				triggerClientEvent(otherPlayers, "playPokerSound", resourceRoot, tableId, "saybet")
			end

			playerTimeoutTimers[tableId] = setTimer(setPlayerFolded, interactionTime, 1, tableId, activeSeat, true)
		end
	end
end

function endPhase(tableId)
	local pokerTable = tablePositions[tableId]

	if pokerTable then
		if playerTimeoutTimers[tableId] then
			if isTimer(playerTimeoutTimers[tableId]) then
				killTimer(playerTimeoutTimers[tableId])
			end

			playerTimeoutTimers[tableId] = nil
		end

		setPokerBoardData(tableId, "currentPlayer", 0)

		sleep(1200)

		local gameStage = getPokerBoardData(tableId, "gameStage") or 0

		if gameStage <= 4 then
			resolveSidePots(tableId)
			setPokerBoardData(tableId, "currentCall", 0)
		end

		if gameStage < 3 then
			if gameStage == 0 then
				local boardCards = {}

				for i = 1, 3 do
					boardCards[i] = table.remove(pokerDeckCards[tableId])
				end

				setPokerBoardData(tableId, "boardCards", boardCards)
			elseif gameStage > 0 then
				local boardCards = getPokerBoardData(tableId, "boardCards") or {}

				if #boardCards < 5 then
					boardCards[#boardCards + 1] = table.remove(pokerDeckCards[tableId])
				end

				setPokerBoardData(tableId, "boardCards", boardCards)
			end

			setPokerBoardData(tableId, "gameStage", gameStage + 1)

			sleep(1000)

			local allInCounter = 0
			local inHandCounter = 0

			for i = 1, maximumPlayers do
				local playerElement = getPokerSeatData(tableId, i, "element")

				if isElement(playerElement) then
					local pokerCoins = getPokerSeatData(tableId, i, "pokerCoins") or 0
					local pokerCards = getPokerSeatData(tableId, i, "pokerCards") or {}

					if pokerCoins == 0 then
						allInCounter = allInCounter + 1
					end

					if #pokerCards > 0 then
						inHandCounter = inHandCounter + 1
					end
				end
			end

			local dealerSeat = getPokerBoardData(tableId, "dealerSeat")
			local newActiveSeat = false

			if allInCounter >= inHandCounter - 1 then
				newActiveSeat = findNextPlayer(tableId, dealerSeat, false, true)
			else
				newActiveSeat = findNextPlayer(tableId, dealerSeat)
			end

			setPokerBoardData(tableId, "lastPlayer", findPreviousPlayer(tableId, newActiveSeat))

			if allInCounter >= inHandCounter - 1 then
				local boardCards = getPokerBoardData(tableId, "boardCards") or {}

				if #boardCards < 5 then
					local numOfCardsRequired = 5 - #boardCards

					if numOfCardsRequired > 0 then
						for i = 1, numOfCardsRequired do
							boardCards[#boardCards + 1] = table.remove(pokerDeckCards[tableId])
						end
					end

					setPokerBoardData(tableId, "boardCards", boardCards)
				end

				setPokerBoardData(tableId, "gameStage", 3)
				execute(endPhase, tableId)
			else
				setPokerBoardData(tableId, "currentPlayer", newActiveSeat)
			end
		elseif gameStage == 3 then
			local showDown = getPokerBoardData(tableId, "showdown")

			if not showDown then
				triggerClientEvent("playPokerSound", resourceRoot, tableId, "sayletsee")

				setPokerBoardData(tableId, "gameStage", 4)
				setPokerBoardData(tableId, "showdown", true)

				execute(determineWinners, tableId)
			end
		end
	end
end

function determineWinners(tableId)
	local pokerTable = tablePositions[tableId]

	if pokerTable then
		sleep(3000)

		local boardCards = getPokerBoardData(tableId, "boardCards") or {}
		local evaluatedHands = {}

		for i = 1, maximumPlayers do
			local playerElement = getPokerSeatData(tableId, i, "element")

			if isElement(playerElement) then
				local pokerCards = getPokerSeatData(tableId, i, "pokerCards") or {}

				if #pokerCards > 0 then
					evaluatedHands[i] = {evaluateResult(pokerCards, boardCards)}
				end
			end
		end

		local winnedRewards = {}

		for i = #pokerBoardPots[tableId], 1, -1 do
			local thisPot = pokerBoardPots[tableId][i]

			if thisPot then
				local winnerList = {}
				local bestRating = 0

				for j = 1, maximumPlayers do
					local playerElement = getPokerSeatData(tableId, j, "element")

					if isElement(playerElement) then
						local evaluatedHand = evaluatedHands[j]

						if evaluatedHand then
							if thisPot.contributors[j] then
								if evaluatedHand[2] > bestRating then
									bestRating = evaluatedHand[2]
									winnerList = {j}
								elseif evaluatedHand[2] == bestRating then
									table.insert(winnerList, j)
								end
							end
						end
					end
				end

				local winnersCount = #winnerList

				if winnersCount > 0 then
					if winnersCount == 1 then
						local winnerSeat = winnerList[1]

						if not winnedRewards[winnerSeat] then
							winnedRewards[winnerSeat] = thisPot.amount
						else
							winnedRewards[winnerSeat] = winnedRewards[winnerSeat] + thisPot.amount
						end
					else
						local averageAmount = math.floor(thisPot.amount / winnersCount)

						if averageAmount > 0 then
							for j = 1, winnersCount do
								local winnerSeat = winnerList[j]

								if not winnedRewards[winnerSeat] then
									winnedRewards[winnerSeat] = averageAmount
								else
									winnedRewards[winnerSeat] = winnedRewards[winnerSeat] + averageAmount
								end
							end
						end
					end
				end
			end
		end

		local remainingDistribution = 0

		for winnerSeat in pairs(winnedRewards) do
			remainingDistribution = remainingDistribution + 1
		end

		if remainingDistribution > 0 then
			for winnerSeat, rewardAmount in pairs(winnedRewards) do
				local winnerPlayer = getPokerSeatData(tableId, winnerSeat, "element")

				if isElement(winnerPlayer) then
					local playerName = exports.global:getPlayerName(winnerPlayer)
					local pokerCoins = getPokerSeatData(tableId, winnerSeat, "pokerCoins") or 0

					pokerCoins = pokerCoins + rewardAmount

					setPokerSeatData(tableId, winnerSeat, "pokerCoins", pokerCoins)
					setPokerSeatData(tableId, winnerSeat, "win", rewardAmount)

					setElementData(winnerPlayer, "playerIcons", {"plus", rewardAmount})

					if playerName then
						local evaluatedHand = evaluatedHands[winnerSeat]

						if evaluatedHand then
							addPokerChatLine("#3d7abc[" .. playerName .. "]: #ffffffNyeremény: " .. thousandsStepper(rewardAmount) .. " Coin (" .. evaluatedHand[1] .. ")", tableId)
						else
							addPokerChatLine("#3d7abc[" .. playerName .. "]: #ffffffNyeremény: " .. thousandsStepper(rewardAmount) .. " Coin", tableId)
						end
					end

					triggerClientEvent(winnerPlayer, "playPokerSound", resourceRoot, tableId, "saywin")

					if remainingDistribution > 1 then
						sleep(1200)
					end
				end

				remainingDistribution = remainingDistribution - 1
			end

			sleep(5000)
		else
			sleep(3000)
		end

		prepareNextRound(tableId, true)
	end
end

function givePotToWinner(tableId, winnerSeat)
	local pokerTable = tablePositions[tableId]

	if pokerTable then
		local playerElement = getPokerSeatData(tableId, winnerSeat, "element")

		if isElement(playerElement) then
			local rewardAmount = getPokerBoardData(tableId, "pot") or 0

			if rewardAmount > 0 then
				local playerName = exports.global:getPlayerName(playerElement)
				local pokerCoins = getPokerSeatData(tableId, winnerSeat, "pokerCoins") or 0

				pokerCoins = pokerCoins + rewardAmount

				setPokerSeatData(tableId, winnerSeat, "pokerCoins", pokerCoins)
				setPokerSeatData(tableId, winnerSeat, "win", rewardAmount)

				setElementData(playerElement, "playerIcons", {"plus", rewardAmount})

				if playerName then
					addPokerChatLine("#3d7abc[" .. playerName .. "]: #ffffffNyeremény: " .. thousandsStepper(rewardAmount) .. " Coin", tableId)
				end

				triggerClientEvent(playerElement, "playPokerSound", resourceRoot, tableId, "saywin")
			end
		end
		pokerBoardPots[tableId] = {}
		setPokerBoardData(tableId, "pot", 0)
	end
end

function evaluateResult(playerCards, boardCards)
	local evaluationRank = false
	local evaluationName = ""
	local evaluationCards = {}

	local mergedCards = {}

	for i = 1, #playerCards do
		mergedCards[i] = playerCards[i]
	end

	for i = 1, #boardCards do
		mergedCards[#mergedCards + 1] = boardCards[i]
	end

	table.sort(mergedCards,
		function (a, b)
			if a[1] > b[1] then
				return true
			elseif a[1] <= b[1] then
				return false
			end
		end
	)

	local flushesOfCards    = {}
	local straightsOfCards  = {}
	local pairsOfCards      = {}

	for i = 1, #cardSuits do
		flushesOfCards[i] = {}
	end

	local theFirstCard = mergedCards[1]

	table.insert(flushesOfCards[theFirstCard[2]], theFirstCard)
	table.insert(straightsOfCards, theFirstCard)

	for i = 2, 7 do
		local currentCard = mergedCards[i]
		local currentCardValue = currentCard[1]

		local previousCard = mergedCards[i - 1]
		local previousCardValue = previousCard[1]

		table.insert(flushesOfCards[currentCard[2]], currentCard)

		if currentCardValue + 1 == previousCardValue then
			table.insert(straightsOfCards, currentCard)
		elseif currentCardValue ~= previousCardValue then
			if #straightsOfCards < 5 then
				straightsOfCards = {currentCard}
			end
		elseif currentCardValue == previousCardValue then
			if not pairsOfCards[currentCardValue] then
				pairsOfCards[currentCardValue] = {previousCard, currentCard}
			else
				table.insert(pairsOfCards[currentCardValue], currentCard)
			end
		end
	end

	if #straightsOfCards >= 4 then
		if straightsOfCards[#straightsOfCards][1] == 1 and theFirstCard[1] == 13 then
			table.insert(straightsOfCards, theFirstCard)
		end

		if #straightsOfCards >= 5 then
			evaluationRank = handRankings.STRAIGHT
			evaluationName = evaluationNames.STRAIGHT
			evaluationCards = {}

			for i = 1, 5 do
				evaluationCards[i] = straightsOfCards[i]
			end
		end
	end

	for i = 1, #flushesOfCards do
		local flushCards = flushesOfCards[i]

		if #flushCards >= 5 then
			if evaluationRank == handRankings.STRAIGHT then
				local straightFlush = {flushCards[1]}

				for j = 2, #flushCards do
					local currentCard = flushCards[j]
					local currentCardValue = currentCard[1]

					local previousCard = flushCards[j - 1]
					local previousCardValue = previousCard[1]

					if currentCardValue + 1 == previousCardValue then
						table.insert(straightFlush, currentCard)
					elseif currentCardValue ~= previousCardValue then
						if #straightFlush < 5 then
							straightFlush = {currentCard}
						end
					end

					if #straightFlush >= 5 then
						break
					end
				end

				local isAceFound = false

				for j = 1, #mergedCards do
					if mergedCards[j][1] == 13 and mergedCards[j][2] == i then
						isAceFound = true
						break
					end
				end

				if #straightFlush == 4 then
					if straightFlush[#straightFlush][1] == 1 and isAceFound then
						table.insert(straightFlush, {13, i})
					end
				end

				if #straightFlush == 5 then
					evaluationCards = straightFlush

					if evaluationCards[1][1] == 13 then
						evaluationRank = handRankings.ROYAL_FLUSH
						evaluationName = evaluationNames.ROYAL_FLUSH
					else
						evaluationRank = handRankings.STRAIGHT_FLUSH
						evaluationName = evaluationNames.STRAIGHT_FLUSH
					end
				end
			end

			if evaluationRank ~= handRankings.ROYAL_FLUSH and evaluationRank ~= handRankings.STRAIGHT_FLUSH then
				evaluationRank = handRankings.FLUSH
				evaluationName = evaluationNames.FLUSH
				evaluationCards = {}

				for i = 1, 5 do
					evaluationCards[i] = flushCards[i]
				end
			end

			break
		end
	end

	if not evaluationRank then
		local numberOfPairs = 0
		local pairKeys = {}

		for cardRank in pairs(pairsOfCards) do
			numberOfPairs = numberOfPairs + 1
			pairKeys[numberOfPairs] = cardRank
		end

		table.sort(pairKeys)

		if numberOfPairs > 0 then
			local kickersCounter = 0

			if numberOfPairs == 1 then
				local maximumKicker = 0

				evaluationCards = pairsOfCards[pairKeys[1]]

				if #evaluationCards == 2 then
					evaluationRank = handRankings.ONE_PAIR
					evaluationName = evaluationNames.ONE_PAIR
					maximumKicker = 3
				elseif #evaluationCards == 3 then
					evaluationRank = handRankings.THREE_OF_A_KIND
					evaluationName = evaluationNames.THREE_OF_A_KIND
					maximumKicker = 2
				elseif #evaluationCards == 4 then
					evaluationRank = handRankings.FOUR_OF_A_KIND
					evaluationName = evaluationNames.FOUR_OF_A_KIND
					maximumKicker = 1
				end

				for i = 1, #mergedCards do
					local currentCard = mergedCards[i]

					if currentCard[1] ~= evaluationCards[1][1] then
						table.insert(evaluationCards, currentCard)
						kickersCounter = kickersCounter + 1
					end

					if kickersCounter >= maximumKicker then
						break
					end
				end
			elseif numberOfPairs == 2 then
				local firstPairRank = pairKeys[1]
				local secondPairRank = pairKeys[2]

				if #pairsOfCards[firstPairRank] > #pairsOfCards[secondPairRank] or (#pairsOfCards[firstPairRank] == #pairsOfCards[secondPairRank] and firstPairRank > secondPairRank) then
					evaluationCards = pairsOfCards[firstPairRank]
					table.remove(pairKeys, 1)
					firstPairRank = pairKeys[1]
				else
					evaluationCards = pairsOfCards[secondPairRank]
					table.remove(pairKeys, 2)
					firstPairRank = pairKeys[1]
				end

				if #evaluationCards == 2 then
					evaluationRank = handRankings.TWO_PAIRS
					evaluationName = evaluationNames.TWO_PAIRS

					for i = 1, 2 do
						table.insert(evaluationCards, pairsOfCards[firstPairRank][i])
					end

					for i = 1, #mergedCards do
						local currentCard = mergedCards[i]

						if currentCard[1] ~= evaluationCards[1][1] and currentCard[1] ~= evaluationCards[3][1] then
							table.insert(evaluationCards, currentCard)
							kickersCounter = kickersCounter + 1
						end

						if kickersCounter >= 1 then
							break
						end
					end
				elseif #evaluationCards == 3 then
					evaluationRank = handRankings.FULL_HOUSE
					evaluationName = evaluationNames.FULL_HOUSE

					for i = 1, 2 do
						table.insert(evaluationCards, pairsOfCards[firstPairRank][i])
					end
				else
					evaluationRank = handRankings.FOUR_OF_A_KIND
					evaluationName = evaluationNames.FOUR_OF_A_KIND

					for i = 1, #mergedCards do
						local currentCard = mergedCards[i]

						if currentCard[1] ~= evaluationCards[1][1] then
							table.insert(evaluationCards, currentCard)
							kickersCounter = kickersCounter + 1
						end

						if kickersCounter >= 1 then
							break
						end
					end
				end
			else
				for cardRank in pairs(pairsOfCards) do
					if #pairsOfCards[cardRank] == 3 then
						evaluationRank = handRankings.FULL_HOUSE
						evaluationName = evaluationNames.FULL_HOUSE
						evaluationCards = pairsOfCards[cardRank]
						pairsOfCards[cardRank] = nil
						break
					end
				end

				local pairRanks = {pairKeys[1], pairKeys[2], pairKeys[3]}

				if #evaluationCards == 0 then
					evaluationRank = handRankings.TWO_PAIRS
					evaluationName = evaluationNames.TWO_PAIRS

					if pairRanks[1] > pairRanks[2] then
						if pairRanks[1] > pairRanks[3] then
							evaluationCards = pairsOfCards[pairRanks[1]]
							table.remove(pairKeys, 1)
						else
							evaluationCards = pairsOfCards[pairRanks[3]]
							table.remove(pairKeys, 3)
						end
					else
						if pairRanks[2] > pairRanks[3] then
							evaluationCards = pairsOfCards[pairRanks[2]]
							table.remove(pairKeys, 2)
						else
							evaluationCards = pairsOfCards[pairRanks[3]]
							table.remove(pairKeys, 3)
						end
					end
				end

				if pairKeys[1] > pairKeys[2] then
					for i = 1, 2 do
						table.insert(evaluationCards, pairsOfCards[pairKeys[1]][i])
					end
				else
					for i = 1, 2 do
						table.insert(evaluationCards, pairsOfCards[pairKeys[2]][i])
					end
				end

				if evaluationRank == handRankings.TWO_PAIRS then
					for i = 1, #mergedCards do
						local currentCard = mergedCards[i]

						if currentCard[1] ~= evaluationCards[1][1] and currentCard[1] ~= evaluationCards[3][1] then
							table.insert(evaluationCards, currentCard)
							kickersCounter = kickersCounter + 1
						end

						if kickersCounter >= 1 then
							break
						end
					end
				end
			end
		end
	end

	if not evaluationRank then
		evaluationRank = handRankings.HIGH_HAND
		evaluationName = evaluationNames.HIGH_HAND
		evaluationCards = {}

		for i = 1, 5 do
			evaluationCards[i] = mergedCards[i]
		end
	end

	local evaluationRate = 0
	local evaluatedRanks = {}

	for i = 1, 5 do
		evaluatedRanks[i] = evaluationCards[i][1]
	end

	evaluationRate = evaluationRate + evaluatedRanks[1] * 30941
	evaluationRate = evaluationRate + evaluatedRanks[2] * 2380
	evaluationRate = evaluationRate + evaluatedRanks[3] * 183
	evaluationRate = evaluationRate + evaluatedRanks[4] * 14
	evaluationRate = evaluationRate + evaluatedRanks[5]

	if secondaryValues[evaluationRank] then
		evaluationRate = evaluationRate + secondaryValues[evaluationRank]
	end

	return evaluationName, evaluationRate
end

function table:shuffle()
	local iterations = #self
	local j

	for i = iterations, 2, -1 do
		j = math.random(i)
		self[i], self[j] = self[j], self[i]
	end
end
