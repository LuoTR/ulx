--Sandbox settings module for ULX GUI -- by Stickly Man!
--Defines sbox cvar limits and sandbox specific settings for the sandbox gamemode.

xgui.prepareDataType( "sboxlimits" )
local sbox_settings = xlib.makepanel{ parent=xgui.null }

xlib.makecheckbox{ x=10, y=10, label="启用穿墙模式", repconvar="rep_sbox_noclip", parent=sbox_settings }
xlib.makecheckbox{ x=10, y=30, label="启用无敌模式", repconvar="rep_sbox_godmode", parent=sbox_settings }
xlib.makecheckbox{ x=10, y=50, label="启用PvP上海", repconvar="rep_sbox_playershurtplayers", parent=sbox_settings }
xlib.makecheckbox{ x=10, y=70, label="带武器出生", repconvar="rep_sbox_weapons", parent=sbox_settings }
xlib.makecheckbox{ x=10, y=90, label="物理枪限制", repconvar="rep_physgun_limited", parent=sbox_settings }

xlib.makecheckbox{ x=10, y=130, label="永久物品", repconvar="rep_sbox_persist", parent=sbox_settings }
xlib.makecheckbox{ x=10, y=150, label="操纵其它东西的骨骼", repconvar="rep_sbox_bonemanip_misc", parent=sbox_settings }
xlib.makecheckbox{ x=10, y=170, label="操纵NPC的骨骼", repconvar="rep_sbox_bonemanip_npc", parent=sbox_settings }
xlib.makecheckbox{ x=10, y=190, label="操纵玩家的骨骼", repconvar="rep_sbox_bonemanip_player", parent=sbox_settings }

xlib.makelabel{ x=5, y=247, w=140, wordwrap=true, label="提示：XGUI中提供的非ULX控制台变量只是为了方便访问，并不会在服务器关闭或崩溃后保存。", parent=sbox_settings }
sbox_settings.plist = xlib.makelistlayout{ x=140, y=5, h=322, w=440, spacing=1, padding=2, parent=sbox_settings }

function sbox_settings.processLimits()
	sbox_settings.plist:Clear()
	for g, limits in ipairs( xgui.data.sboxlimits ) do
		if #limits > 0 then
			local panel = xlib.makepanel{ h=5+math.ceil( #limits/2 )*25 }
			local i=0
			for _, cvar in ipairs( limits ) do
				local cvardata = string.Explode( " ", cvar ) --Split the cvarname and max slider value number
				xgui.queueFunctionCall( xlib.makeslider, "sboxlimits", { x=10+(i%2*205), y=5+math.floor(i/2)*25, w=200, label="Max " .. cvardata[1]:sub(9), min=0, max=cvardata[2], repconvar="rep_"..cvardata[1], parent=panel, fixclip=true } )
				i = i + 1
			end
			sbox_settings.plist:Add( xlib.makecat{ label=limits.title .. " （限制 " .. #limits .. " 个）", contents=panel, expanded=( g==1 ) } )
		end
	end
end
sbox_settings.processLimits()

xgui.hookEvent( "sboxlimits", "process", sbox_settings.processLimits, "sandboxProcessLimits" )
xgui.addSettingModule( "沙盒", sbox_settings, "icon16/box.png", "xgui_gmsettings" )
