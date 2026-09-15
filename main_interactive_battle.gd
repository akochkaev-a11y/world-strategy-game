extends "res://main_game_tuning.gd"

const TACTICAL_KEYS := ["army", "air", "navy", "def", "missile"]
const TACTICAL_NAMES := {"army":"Сухопутные", "air":"Авиация", "navy":"Флот", "def":"ПВО/ПРО", "missile":"Ракеты"}
const TACTICAL_SYMBOLS := {"army":"■", "air":"▲", "navy":"◆", "def":"⬟", "missile":"●"}
const TACTICAL_COLORS := {"army":Color("63d471"), "air":Color("57c7ff"), "navy":Color("4d7cff"), "def":Color("ffd166"), "missile":Color("ff5d73")}
const ZONES := ["СЕВЕР", "ЦЕНТР", "ЮГ"]
var tactical_active := false

class BattleField:
    extends Control
    signal order_sent(key, zone, share)
    var source_rects := {}
    var zone_rects := {}
    var forces := {}
    var enemy := {}
    var moving := []
    var flashes := []
    var drag_key := ""
    var drag_from := Vector2.ZERO
    var drag_to := Vector2.ZERO
    var dragging := false
    var pulse := 0.0

    func setup(pforces:Dictionary, eforces:Dictionary)->void:
        forces=pforces; enemy=eforces
        mouse_filter=Control.MOUSE_FILTER_STOP
        set_process(true)
        queue_redraw()

    func _process(delta:float)->void:
        pulse += delta
        for m in moving:
            m.t = minf(1.0,float(m.t)+delta*float(m.speed))
        for i in range(moving.size()-1,-1,-1):
            if float(moving[i].t)>=1.0: moving.remove_at(i)
        for i in range(flashes.size()-1,-1,-1):
            flashes[i].life=float(flashes[i].life)-delta
            if float(flashes[i].life)<=0.0: flashes.remove_at(i)
        queue_redraw()

    func launch(key:String, zone:String, amount:float)->void:
        if amount<=0.0 or not source_rects.has(key) or not zone_rects.has(zone): return
        var start:Vector2=source_rects[key].get_center()
        var finish:Vector2=zone_rects[zone].get_center()
        var count:=clampi(int(4.0+sqrt(amount/maxf(1.0,10000.0))*2.5),4,22)
        for i in range(count):
            moving.append({"key":key,"from":start+Vector2(randf_range(-12,12),randf_range(-12,12)),"to":finish+Vector2(randf_range(-35,35),randf_range(-24,24)),"t":-float(i)*0.035,"speed":randf_range(0.75,1.15)})

    func hit(zone:String)->void:
        if zone_rects.has(zone): flashes.append({"pos":zone_rects[zone].get_center()+Vector2(randf_range(-45,45),randf_range(-25,25)),"life":0.35})

    func _gui_input(event:InputEvent)->void:
        var pos:=Vector2.ZERO
        var press:=false; var release:=false; var motion:=false
        if event is InputEventScreenTouch:
            pos=event.position; press=event.pressed; release=not event.pressed
        elif event is InputEventScreenDrag:
            pos=event.position; motion=true
        elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
            pos=event.position; press=event.pressed; release=not event.pressed
        elif event is InputEventMouseMotion and dragging:
            pos=event.position; motion=true
        else: return
        if press:
            for key in source_rects:
                if source_rects[key].has_point(pos) and float(forces.get(key,0.0))>0.0:
                    drag_key=key; drag_from=source_rects[key].get_center(); drag_to=pos; dragging=true; accept_event(); return
        if motion and dragging:
            drag_to=pos; queue_redraw(); accept_event(); return
        if release and dragging:
            drag_to=pos
            var target:=""
            for zone in zone_rects:
                if zone_rects[zone].has_point(pos): target=zone
            if target!="":
                var distance:=drag_from.distance_to(pos)
                var share:=0.25 if distance<size.x*0.42 else (0.50 if distance<size.x*0.62 else 1.0)
                order_sent.emit(drag_key,target,share)
            dragging=false; drag_key=""; queue_redraw(); accept_event()

    func _draw()->void:
        var w:=size.x; var h:=size.y
        draw_rect(Rect2(Vector2.ZERO,size),Color("163f39"))
        for i in range(9):
            var y:=h*float(i)/8.0
            draw_line(Vector2(0,y),Vector2(w,y),Color(0.18,0.42,0.31,0.35),2)
        draw_circle(Vector2(w*0.50,h*0.50),minf(w,h)*0.18,Color(0.10,0.24,0.19,0.55))
        draw_line(Vector2(w*0.5,0),Vector2(w*0.5,h),Color(1,1,1,0.16),3)
        var row_h:=h/5.0
        for i in range(TACTICAL_KEYS.size()):
            var key:String=TACTICAL_KEYS[i]
            var r:=Rect2(12,8+i*row_h,w*0.19,row_h-12)
            source_rects[key]=r
            draw_style_box(_box(TACTICAL_COLORS[key],Color(0.03,0.08,0.10,0.92)),r)
            draw_string(ThemeDB.fallback_font,r.position+Vector2(10,22),"%s %s" % [TACTICAL_SYMBOLS[key],TACTICAL_NAMES[key]],HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color.WHITE)
            draw_string(ThemeDB.fallback_font,r.position+Vector2(10,44),_compact(float(forces.get(key,0.0))),HORIZONTAL_ALIGNMENT_LEFT,-1,17,TACTICAL_COLORS[key])
            var er:=Rect2(w-r.size.x-12,r.position.y,r.size.x,r.size.y)
            draw_style_box(_box(Color("ff6b5f"),Color(0.20,0.055,0.055,0.92)),er)
            draw_string(ThemeDB.fallback_font,er.position+Vector2(10,22),"%s %s" % [TACTICAL_SYMBOLS[key],TACTICAL_NAMES[key]],HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color.WHITE)
            draw_string(ThemeDB.fallback_font,er.position+Vector2(10,44),_compact(float(enemy.get(key,0.0))),HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("ff9a91"))
        var center_left:=w*0.27; var center_width:=w*0.46
        for i in range(ZONES.size()):
            var zh:=h/3.0
            var zr:=Rect2(center_left,8+i*zh,center_width,zh-16)
            zone_rects[ZONES[i]]=zr
            var glow:=0.05+0.025*sin(pulse*2.0+i)
            draw_style_box(_box(Color(0.28,0.76,0.50,0.55),Color(0.04+glow,0.15+glow,0.12+glow,0.78)),zr)
            draw_string(ThemeDB.fallback_font,zr.position+Vector2(12,24),ZONES[i],HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("dfffe8"))
        for m in moving:
            var t:=clampf(float(m.t),0.0,1.0); var p:Vector2=Vector2(m.from).lerp(Vector2(m.to),t); _draw_unit(str(m.key),p,TACTICAL_COLORS[str(m.key)])
        for f in flashes:
            var rad:=26.0*float(f.life)/0.35+5.0
            draw_circle(Vector2(f.pos),rad,Color(1.0,0.55,0.12,0.55))
            draw_circle(Vector2(f.pos),rad*0.45,Color(1.0,0.95,0.55,0.9))
        if dragging:
            draw_line(drag_from,drag_to,Color("fff08a"),7,true)
            var dir:=(drag_to-drag_from).normalized()
            if dir.length()>0.1:
                var tip:=drag_to; draw_colored_polygon(PackedVector2Array([tip,tip-dir*22+dir.rotated(1.57)*10,tip-dir*22+dir.rotated(-1.57)*10]),Color("fff08a"))

    func _box(border:Color,bg:Color)->StyleBoxFlat:
        var s:=StyleBoxFlat.new(); s.bg_color=bg; s.border_color=border; s.set_border_width_all(3); s.set_corner_radius_all(12); return s
    func _compact(v:float)->String:
        if v>=1000000.0: return "%.2f млн"%(v/1000000.0)
        if v>=1000.0: return "%.0f тыс"%(v/1000.0)
        return "%.0f"%v
    func _draw_unit(key:String,p:Vector2,c:Color)->void:
        if key=="army": draw_rect(Rect2(p-Vector2(5,5),Vector2(10,10)),c)
        elif key=="air": draw_colored_polygon(PackedVector2Array([p+Vector2(0,-7),p+Vector2(-7,6),p+Vector2(7,6)]),c)
        elif key=="navy": draw_colored_polygon(PackedVector2Array([p+Vector2(0,-7),p+Vector2(-8,0),p+Vector2(0,7),p+Vector2(8,0)]),c)
        elif key=="def": draw_circle(p,7,c); draw_circle(p,4,Color("163f39"))
        else: draw_circle(p,5,c); draw_line(p-Vector2(14,0),p-Vector2(5,0),Color(1,0.7,0.2,0.65),3)

func _resolve_battle(attacker_id:String,defender_id:String,attack_fraction:float,silent_bot:bool=false)->void:
    if attacker_id!=player_id and defender_id!=player_id: super._resolve_battle(attacker_id,defender_id,attack_fraction,silent_bot); return
    if tactical_active or _are_allies(attacker_id,defender_id): return
    _start_tactical_battle(attacker_id,defender_id,attack_fraction)

func _start_tactical_battle(attacker_id:String,defender_id:String,attack_fraction:float)->void:
    tactical_active=true; var old_paused:=paused; paused=true
    var ps:=attacker_id if attacker_id==player_id else defender_id; var es:=defender_id if attacker_id==player_id else attacker_id
    var reserve:={}; var ereserve:={}; var initial:={}; var einitial:={}
    for key in TACTICAL_KEYS:
        reserve[key]=float(countries[ps][key])*(attack_fraction if ps==attacker_id else 1.0); ereserve[key]=float(countries[es][key])*(1.0 if es==defender_id else attack_fraction); initial[key]=reserve[key]; einitial[key]=ereserve[key]
    var dep:={}; var edep:={}
    for z in ZONES:
        dep[z]={}; edep[z]={}
        for key in TACTICAL_KEYS: dep[z][key]=0.0; edep[z][key]=float(ereserve[key])/3.0
    var overlay:=ColorRect.new(); overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); overlay.color=Color("081b25"); overlay.mouse_filter=Control.MOUSE_FILTER_STOP; overlay.z_index=700; add_child(overlay)
    var root:=VBoxContainer.new(); root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.offset_left=8; root.offset_right=-8; root.offset_top=8; root.offset_bottom=-8; overlay.add_child(root)
    var title:=Label.new(); title.text="%s  ⚔  %s"%[countries[ps].name,countries[es].name]; title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; title.add_theme_font_size_override("font_size",22); root.add_child(title)
    var help:=Label.new(); help.text="ТЯНИ ПАЛЬЦЕМ ОТ СВОИХ ВОЙСК К СЕКТОРУ • ближе 25% • дальше 50% • до противника 100%"; help.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; help.add_theme_font_size_override("font_size",13); root.add_child(help)
    var field:=BattleField.new(); field.size_flags_vertical=Control.SIZE_EXPAND_FILL; field.size_flags_horizontal=Control.SIZE_EXPAND_FILL; field.custom_minimum_size=Vector2(700,420); root.add_child(field); field.setup(reserve,ereserve)
    var status:=Label.new(); status.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; status.text="Захватывайте направления и перебрасывайте подкрепления прямо во время боя"; root.add_child(status)
    var finish:=Button.new(); finish.text="ЗАВЕРШИТЬ БОЙ"; finish.custom_minimum_size.y=54; root.add_child(finish)
    field.order_sent.connect(func(key:String,zone:String,share:float):
        var send:=float(reserve[key])*share
        if send<=0.0:return
        reserve[key]-=send; dep[zone][key]=float(dep[zone][key])+send; field.launch(key,zone,send)
    )
    var done:=[false]; finish.pressed.connect(func():done[0]=true); var elapsed:=0.0
    while not done[0] and is_instance_valid(overlay):
        await get_tree().create_timer(0.22,true,false,true).timeout; elapsed+=0.22
        _tactical_combat_step(dep,edep)
        if randf()<0.55: field.hit(ZONES.pick_random())
        if elapsed>0.8:
            for key in TACTICAL_KEYS:
                if float(ereserve[key])>0.0 and randf()<0.22:
                    var z:String=ZONES.pick_random(); var send:=float(ereserve[key])*randf_range(0.04,0.10); ereserve[key]-=send; edep[z][key]=float(edep[z][key])+send
        field.forces=reserve; field.enemy=_totals(ereserve,edep); field.queue_redraw()
        if elapsed>=60.0:done[0]=true
    if is_instance_valid(overlay):overlay.queue_free()
    _finish_tactical_battle(ps,es,attacker_id,defender_id,initial,einitial,reserve,ereserve,dep,edep); paused=old_paused; tactical_active=false

func _totals(reserve:Dictionary,dep:Dictionary)->Dictionary:
    var out:={}
    for key in TACTICAL_KEYS:
        out[key]=float(reserve[key])
        for z in ZONES: out[key]+=float(dep[z][key])
    return out

func _tactical_combat_step(ours:Dictionary,theirs:Dictionary)->void:
    for z in ZONES:
        var a:Dictionary=ours[z]; var d:Dictionary=theirs[z]
        for key in ["army","air","navy"]:
            var av:=float(a[key]); var dv:=float(d[key])
            if av>0.0 and dv>0.0:
                a[key]=maxf(0.0,av-minf(av,dv*randf_range(0.003,0.009))); d[key]=maxf(0.0,dv-minf(dv,av*randf_range(0.003,0.009)))
        if float(a.def)>0 and float(d.air)>0:d.air=maxf(0,float(d.air)-float(a.def)*randf_range(0.002,0.006))
        if float(d.def)>0 and float(a.air)>0:a.air=maxf(0,float(a.air)-float(d.def)*randf_range(0.002,0.006))
        d.army=maxf(0,float(d.army)-float(a.air)*0.0015-float(a.navy)*0.001); a.army=maxf(0,float(a.army)-float(d.air)*0.0015-float(d.navy)*0.001)
        var amp:=maxf(0,float(a.missile)-float(d.def)*0.012); var dmp:=maxf(0,float(d.missile)-float(a.def)*0.012)
        if amp>0:d.army=maxf(0,float(d.army)-amp*0.8);d.air=maxf(0,float(d.air)-amp*0.18);d.navy=maxf(0,float(d.navy)-amp*0.12);a.missile=maxf(0,float(a.missile)-amp*0.02)
        if dmp>0:a.army=maxf(0,float(a.army)-dmp*0.8);a.air=maxf(0,float(a.air)-dmp*0.18);a.navy=maxf(0,float(a.navy)-dmp*0.12);d.missile=maxf(0,float(d.missile)-dmp*0.02)
        if float(a.army)>0:d.def=maxf(0,float(d.def)-float(a.army)*0.0007)
        if float(d.army)>0:a.def=maxf(0,float(a.def)-float(d.army)*0.0007)

func _finish_tactical_battle(ps:String,es:String,attacker_id:String,defender_id:String,initial:Dictionary,einitial:Dictionary,reserve:Dictionary,ereserve:Dictionary,dep:Dictionary,edep:Dictionary)->void:
    var fp:=_totals(reserve,dep); var fe:=_totals(ereserve,edep)
    for key in TACTICAL_KEYS:
        var pl:=maxf(0,float(initial[key])-float(fp[key])); var el:=maxf(0,float(einitial[key])-float(fe[key])); countries[ps][key]=maxf(0,float(countries[ps][key])-pl); countries[es][key]=maxf(0,float(countries[es][key])-el)
        if key!="missile":countries[ps].population=maxf(0.1,float(countries[ps].population)-pl/1000000.0);countries[es].population=maxf(0.1,float(countries[es].population)-el/1000000.0)
    var pt:=0.0;var et:=0.0
    for key in TACTICAL_KEYS:pt+=float(fp[key]);et+=float(fe[key])
    var winner:=ps if pt>=et else es
    countries[ps].war_fatigue=minf(100,float(countries[ps].war_fatigue)+5);countries[es].war_fatigue=minf(100,float(countries[es].war_fatigue)+5);countries[ps].relations[es]=-100;countries[es].relations[ps]=-100
    _push_news("БИТВА: %s - %s: победа %s (интерактивный бой)."%[countries[attacker_id].name,countries[defender_id].name,countries[winner].name]);_mark_activity(attacker_id,ACTIVITY_WAR,6);_mark_activity(defender_id,ACTIVITY_WAR,6);_refresh_all()
