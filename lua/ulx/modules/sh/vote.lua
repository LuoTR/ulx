local CATEGORY_NAME = "投票"

---------------
--Public vote--
---------------
if SERVER then ulx.convar( "voteEcho", "0", _, ULib.ACCESS_SUPERADMIN ) end -- Echo votes?

if SERVER then
	util.AddNetworkString( "ulx_vote" )
end
-- First, our helper function to make voting so much easier!
function ulx.doVote( title, options, callback, timeout, filter, noecho, ... )
	timeout = timeout or 20
	if ulx.voteInProgress then
		Msg( "错误！ULX在其它投票进行时尝试开始新的投票！\n" )
		return false
	end

	if not options[ 1 ] or not options[ 2 ] then
		Msg( "错误！ULX尝试开始选项少于2个的投票\n" )
		return false
	end

	local voters = 0
	local rp = RecipientFilter()
	if not filter then
		rp:AddAllPlayers()
		voters = #player.GetAll()
	else
		for _, ply in ipairs( filter ) do
			rp:AddPlayer( ply )
			voters = voters + 1
		end
	end
	
	
	net.Start("ulx_vote")
		net.WriteString( title )
		net.WriteInt( timeout, 16 )
		net.WriteTable( options )
	net.Broadcast()
	

	ulx.voteInProgress = { callback=callback, options=options, title=title, results={}, voters=voters, votes=0, noecho=noecho, args={...} }

	timer.Create( "ULXVoteTimeout", timeout, 1, ulx.voteDone )

	return true
end

function ulx.voteCallback( ply, command, argv )
	if not ulx.voteInProgress then
		ULib.tsayError( ply, "当前没有进行中的投票。" )
		return
	end

	if not argv[ 1 ] or not tonumber( argv[ 1 ] ) or not ulx.voteInProgress.options[ tonumber( argv[ 1 ] ) ] then
		ULib.tsayError( ply, "无效或超出范围投票。" )
		return
	end

	if ply.ulxVoted then
		ULib.tsayError( ply, "你已经投过票了！" )
		return
	end

	local echo = ULib.toBool( GetConVarNumber( "ulx_voteEcho" ) )
	local id = tonumber( argv[ 1 ] )
	ulx.voteInProgress.results[ id ] = ulx.voteInProgress.results[ id ] or 0
	ulx.voteInProgress.results[ id ] = ulx.voteInProgress.results[ id ] + 1

	ulx.voteInProgress.votes = ulx.voteInProgress.votes + 1

	ply.ulxVoted = true -- Tag them as having voted

	local str = ply:Nick() .. " 投了： " .. ulx.voteInProgress.options[ id ]
	if echo and not ulx.voteInProgress.noecho then
		ULib.tsay( _, str ) -- TODO, color?
	end
	ulx.logString( str )
	if game.IsDedicated() then Msg( str .. "\n" ) end

	if ulx.voteInProgress.votes >= ulx.voteInProgress.voters then
		ulx.voteDone()
	end
end
if SERVER then concommand.Add( "ulx_vote", ulx.voteCallback ) end

function ulx.voteDone( cancelled )
	local players = player.GetAll()
	for _, ply in ipairs( players ) do -- Clear voting tags
		ply.ulxVoted = nil
	end

	local vip = ulx.voteInProgress
	ulx.voteInProgress = nil
	timer.Remove( "ULXVoteTimeout" )
	if not cancelled then
		ULib.pcallError( vip.callback, vip, unpack( vip.args, 1, 10 ) ) -- Unpack is explicit in length to avoid odd LuaJIT quirk.
	end
end
-- End our helper functions





local function voteDone( t )
	local results = t.results
	local winner
	local winnernum = 0
	for id, numvotes in pairs( results ) do
		if numvotes > winnernum then
			winner = id
			winnernum = numvotes
		end
	end

	local str
	if not winner then
		str = "投票结果：没有选项胜出，因为没人投票。"
	else
		str = "投票结果：选项 '" .. t.options[ winner ] .. "' 胜利。（" .. winnernum .. "/" .. t.voters .. "）"
	end
	ULib.tsay( _, str ) -- TODO, color?
	ulx.logString( str )
	Msg( str .. "\n" )
end

function ulx.vote( calling_ply, title, ... )
	if ulx.voteInProgress then
		ULib.tsayError( calling_ply, "目前已经有投票正在进行。请等待当前投票结束。", true )
		return
	end

	ulx.doVote( title, { ... }, voteDone )
	ulx.fancyLogAdmin( calling_ply, "#A 开始了投票（#s）", title )
end
local vote = ulx.command( CATEGORY_NAME, "ulx vote", ulx.vote, "!vote" )
vote:addParam{ type=ULib.cmds.StringArg, hint="标题" }
vote:addParam{ type=ULib.cmds.StringArg, hint="选项", ULib.cmds.takeRestOfLine, repeat_min=2, repeat_max=10 }
vote:defaultAccess( ULib.ACCESS_ADMIN )
vote:help( "开始公共投票。" )

-- Stop a vote in progress
function ulx.stopVote( calling_ply )
	if not ulx.voteInProgress then
		ULib.tsayError( calling_ply, "当前没有投票正在进行。", true )
		return
	end

	ulx.voteDone( true )
	ulx.fancyLogAdmin( calling_ply, "#A 停止了当前投票。" )
end
local stopvote = ulx.command( CATEGORY_NAME, "ulx stopvote", ulx.stopVote, "!stopvote" )
stopvote:defaultAccess( ULib.ACCESS_SUPERADMIN )
stopvote:help( "停止正在进行的投票。" )

local function voteMapDone2( t, changeTo, ply )
	local shouldChange = false

	if t.results[ 1 ] and t.results[ 1 ] > 0 then
		ulx.logServAct( ply, "#A 通过了换图投票" )
		shouldChange = true
	else
		ulx.logServAct( ply, "#A 拒绝了换图投票" )
	end

	if shouldChange then
		ULib.consoleCommand( "changelevel " .. changeTo .. "\n" )
	end
end

local function voteMapDone( t, argv, ply )
	local results = t.results
	local winner
	local winnernum = 0
	for id, numvotes in pairs( results ) do
		if numvotes > winnernum then
			winner = id
			winnernum = numvotes
		end
	end

	local ratioNeeded = GetConVarNumber( "ulx_votemap2Successratio" )
	local minVotes = GetConVarNumber( "ulx_votemap2Minvotes" )
	local str
	local changeTo
	-- Figure out the map to change to, if we're changing
	if #argv > 1 then
		changeTo = t.options[ winner ]
	else
		changeTo = argv[ 1 ]
	end

	if (#argv < 2 and winner ~= 1) or not winner or winnernum < minVotes or winnernum / t.voters < ratioNeeded then
		str = "投票结果：投票并不成功。"
	elseif ply:IsValid() then
		str = "投票结果：选项 '" .. t.options[ winner ] .. "' 胜出，等待通过换图。（" .. winnernum .. "/" .. t.voters .. "）"

		ulx.doVote( "接受投票结果并将地图换为 " .. changeTo .. "？", { "是", "否" }, voteMapDone2, 30000, { ply }, true, changeTo, ply )
	else -- It's the server console, let's roll with it
		str = "投票结果：选项 '" .. t.options[ winner ] .. "' 胜出。（" .. winnernum .. "/" .. t.voters .. "）"
		ULib.tsay( _, str )
		ulx.logString( str )
		ULib.consoleCommand( "changelevel " .. changeTo .. "\n" )
		return
	end

	ULib.tsay( _, str ) -- TODO, color?
	ulx.logString( str )
	if game.IsDedicated() then Msg( str .. "\n" ) end
end

function ulx.votemap2( calling_ply, ... )
	local argv = { ... }

	if ulx.voteInProgress then
		ULib.tsayError( calling_ply, "目前已经有投票正在进行。请等待当前投票结束。", true )
		return
	end

	for i=2, #argv do
	    if ULib.findInTable( argv, argv[ i ], 1, i-1 ) then
	        ULib.tsayError( calling_ply, "地图 " .. argv[ i ] .. " 出现了两次。请再试一次" )
	        return
	    end
	end

	if #argv > 1 then
		ulx.doVote( "将地图更改为..", argv, voteMapDone, _, _, _, argv, calling_ply )
		ulx.fancyLogAdmin( calling_ply, "#A 开始了地图投票，选项有" .. string.rep( " #s", #argv ), ... )
	else
		ulx.doVote( "将地图更改为 " .. argv[ 1 ] .. "？", { "是", "否" }, voteMapDone, _, _, _, argv, calling_ply )
		ulx.fancyLogAdmin( calling_ply, "#A 投票将地图换为 #s", argv[ 1 ] )
	end
end
local votemap2 = ulx.command( CATEGORY_NAME, "ulx votemap2", ulx.votemap2, "!votemap2" )
votemap2:addParam{ type=ULib.cmds.StringArg, completes=ulx.maps, hint="地图", error="指定的地图 \"%s\" 无效", ULib.cmds.restrictToCompletes, ULib.cmds.takeRestOfLine, repeat_min=1, repeat_max=10 }
votemap2:defaultAccess( ULib.ACCESS_ADMIN )
votemap2:help( "开始一个公开的换图投票。" )
if SERVER then ulx.convar( "votemap2Successratio", "0.5", _, ULib.ACCESS_ADMIN ) end -- The ratio needed for a votemap2 to succeed
if SERVER then ulx.convar( "votemap2Minvotes", "3", _, ULib.ACCESS_ADMIN ) end -- Minimum votes needed for votemap2



local function voteKickDone2( t, target, time, ply, reason )
	local shouldKick = false

	if t.results[ 1 ] and t.results[ 1 ] > 0 then
		ulx.logUserAct( ply, target, "#A 通过了对 #T 的投票踢出（" .. (reason or "") .. "）" )
		shouldKick = true
	else
		ulx.logUserAct( ply, target, "#A 拒绝了对 #T 的投票踢出" )
	end

	if shouldKick then
		if reason and reason ~= "" then
			ULib.kick( target, "投票踢出成功。（" .. reason .. "）" )
		else
			ULib.kick( target, "投票踢出成功。" )
		end
	end
end

local function voteKickDone( t, target, time, ply, reason )
	local results = t.results
	local winner
	local winnernum = 0
	for id, numvotes in pairs( results ) do
		if numvotes > winnernum then
			winner = id
			winnernum = numvotes
		end
	end

	local ratioNeeded = GetConVarNumber( "ulx_votekickSuccessratio" )
	local minVotes = GetConVarNumber( "ulx_votekickMinvotes" )
	local str
	if winner ~= 1 or winnernum < minVotes or winnernum / t.voters < ratioNeeded then
		str = "投票结果：用户不会被踢出。（" .. (results[ 1 ] or "0") .. "/" .. t.voters .. "）"
	else
		if not target:IsValid() then
			str = "投票结果：用户被投票踢出，但其已经离开。"
		elseif ply:IsValid() then
			str = "投票结果：用户将会被踢出，等待通过。（" .. winnernum .. "/" .. t.voters .. "）"
			ulx.doVote( "接受结果并踢出 " .. target:Nick() .. "？", { "是", "否" }, voteKickDone2, 30000, { ply }, true, target, time, ply, reason )
		else -- Vote from server console, roll with it
			str = "投票结果：用户将会被踢出。（" .. winnernum .. "/" .. t.voters .. "）"
			ULib.kick( target, "投票踢出成功。" )
		end
	end

	ULib.tsay( _, str ) -- TODO, color?
	ulx.logString( str )
	if game.IsDedicated() then Msg( str .. "\n" ) end
end

function ulx.votekick( calling_ply, target_ply, reason )
	if target_ply:IsListenServerHost() then
		ULib.tsayError( calling_ply, "该玩家免疫踢出", true )
		return
	end

	if ulx.voteInProgress then
		ULib.tsayError( calling_ply, "目前已经有投票正在进行。请等待当前投票结束。", true )
		return
	end

	local msg = "踢出 " .. target_ply:Nick() .. "？"
	if reason and reason ~= "" then
		msg = msg .. " (" .. reason .. ")"
	end

	ulx.doVote( msg, { "是", "否" }, voteKickDone, _, _, _, target_ply, time, calling_ply, reason )
	if reason and reason ~= "" then
		ulx.fancyLogAdmin( calling_ply, "#A 开始了对 #T 的投票踢出（#s）", target_ply, reason )
	else
		ulx.fancyLogAdmin( calling_ply, "#A 开始了对 #T 的投票踢出", target_ply )
	end
end
local votekick = ulx.command( CATEGORY_NAME, "ulx votekick", ulx.votekick, "!votekick" )
votekick:addParam{ type=ULib.cmds.PlayerArg }
votekick:addParam{ type=ULib.cmds.StringArg, hint="原因", ULib.cmds.optional, ULib.cmds.takeRestOfLine, completes=ulx.common_kick_reasons }
votekick:defaultAccess( ULib.ACCESS_ADMIN )
votekick:help( "开始一个针对目标的投票踢出。" )
if SERVER then ulx.convar( "votekickSuccessratio", "0.6", _, ULib.ACCESS_ADMIN ) end -- The ratio needed for a votekick to succeed
if SERVER then ulx.convar( "votekickMinvotes", "2", _, ULib.ACCESS_ADMIN ) end -- Minimum votes needed for votekick



local function voteBanDone2( t, nick, steamid, time, ply, reason )
	local shouldBan = false

	if t.results[ 1 ] and t.results[ 1 ] > 0 then
		ulx.fancyLogAdmin( ply, "#A 通过了对 #s 的投票封禁（#s 分钟） （#s）", nick, time, reason or "" )
		shouldBan = true
	else
		ulx.fancyLogAdmin( ply, "#A 拒绝了对 #s 的投票封禁", nick )
	end

	if shouldBan then
		ULib.addBan( steamid, time, reason, nick, ply )
	end
end

local function voteBanDone( t, nick, steamid, time, ply, reason )
	local results = t.results
	local winner
	local winnernum = 0
	for id, numvotes in pairs( results ) do
		if numvotes > winnernum then
			winner = id
			winnernum = numvotes
		end
	end

	local ratioNeeded = GetConVarNumber( "ulx_votebanSuccessratio" )
	local minVotes = GetConVarNumber( "ulx_votebanMinvotes" )
	local str
	if winner ~= 1 or winnernum < minVotes or winnernum / t.voters < ratioNeeded then
		str = "投票结果：用户不会被封禁。（" .. (results[ 1 ] or "0") .. "/" .. t.voters .. "）"
	else
		reason = ("[ULX投票封禁] " .. (reason or "")):Trim()
		if ply:IsValid() then
			str = "投票结果：用户将会被封禁，等待通过。（" .. winnernum .. "/" .. t.voters .. "）"
			ulx.doVote( "接受结果并封禁 " .. nick .. "？", { "是", "否" }, voteBanDone2, 30000, { ply }, true, nick, steamid, time, ply, reason )
		else -- Vote from server console, roll with it
			str = "投票结果：用户将会被封禁。（" .. winnernum .. "/" .. t.voters .. "）"
			ULib.addBan( steamid, time, reason, nick, ply )
		end
	end

	ULib.tsay( _, str ) -- TODO, color?
	ulx.logString( str )
	Msg( str .. "\n" )
end

function ulx.voteban( calling_ply, target_ply, minutes, reason )
	if target_ply:IsListenServerHost() or target_ply:IsBot() then
		ULib.tsayError( calling_ply, "该玩家免疫封禁", true )
		return
	end

	if ulx.voteInProgress then
		ULib.tsayError( calling_ply, "目前已经有投票正在进行。请等待当前投票结束。", true )
		return
	end

	local msg = "将 " .. target_ply:Nick() .. " 封禁 " .. minutes .. " 分钟？"
	if reason and reason ~= "" then
		msg = msg .. " （" .. reason .. "）"
	end

	ulx.doVote( msg, { "是", "否" }, voteBanDone, _, _, _, target_ply:Nick(), target_ply:SteamID(), minutes, calling_ply, reason )
	if reason and reason ~= "" then
		ulx.fancyLogAdmin( calling_ply, "#A 开始了将 #T 封禁 #i 分钟的投票（#s）", target_ply, minutes, reason )
	else
		ulx.fancyLogAdmin( calling_ply, "#A 开始了将 #T 封禁 #i 分钟的投票", target_ply, minutes )
	end
end
local voteban = ulx.command( CATEGORY_NAME, "ulx voteban", ulx.voteban, "!voteban" )
voteban:addParam{ type=ULib.cmds.PlayerArg }
voteban:addParam{ type=ULib.cmds.NumArg, min=0, default=1440, hint="分钟", ULib.cmds.allowTimeString, ULib.cmds.optional }
voteban:addParam{ type=ULib.cmds.StringArg, hint="原因", ULib.cmds.optional, ULib.cmds.takeRestOfLine, completes=ulx.common_kick_reasons }
voteban:defaultAccess( ULib.ACCESS_ADMIN )
voteban:help( "开始一个针对目标的公开封禁投票。" )
if SERVER then ulx.convar( "votebanSuccessratio", "0.7", _, ULib.ACCESS_ADMIN ) end -- The ratio needed for a voteban to succeed
if SERVER then ulx.convar( "votebanMinvotes", "3", _, ULib.ACCESS_ADMIN ) end -- Minimum votes needed for voteban

-- Our regular votemap command
local votemap = ulx.command( CATEGORY_NAME, "ulx votemap", ulx.votemap, "!votemap" )
votemap:addParam{ type=ULib.cmds.StringArg, completes=ulx.votemaps, hint="地图", ULib.cmds.takeRestOfLine, ULib.cmds.optional }
votemap:defaultAccess( ULib.ACCESS_ALL )
votemap:help( "为一个地图投票，不带参数则显示可用地图。" )

-- Our veto command
local veto = ulx.command( CATEGORY_NAME, "ulx veto", ulx.votemapVeto, "!veto" )
veto:defaultAccess( ULib.ACCESS_ADMIN )
veto:help( "否决一个成功的投票换图。" )
