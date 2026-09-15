extends "res://main_game_tuning.gd"

var tactical_active: bool = false

const FLAGS := {"RU":"🇷🇺","UA":"🇺🇦","PL":"🇵🇱","FR":"🇫🇷","DE":"🇩🇪","GB":"🇬🇧","CN":"🇨🇳","IN":"🇮🇳","IR":"🇮🇷","JP":"🇯🇵"}

class BattleFront:
    extends Control
    signal send_army(share: float)
    var our_reserve: float = 0.0
    var enemy_reserve: float = 0.0
    var our_column: float = 0.0
    var enemy_column: float = 0.0
    var our_flag: String = "🇷🇺"
    var enemy_flag: String = "🏳️"
    var our_name: String = "Россия"
    var enemy_name: String = "Противник"
    var dragging: bool = false
    var drag_from: Vector2 = Vector2.ZERO
    var drag_to: Vector2 = Vector2.ZERO
    var movers: Array = []
    var blasts: Array = []

    func _process(delta: float) -> void:
        for m in movers: m.t=float(m.t)+delta*float(m.speed)
        for i in range(movers.size()-1,-1,-1):
            if float(movers[i].t)>=1.0: movers.remove_at(i)
        for b in blasts: b.life=float(b.life)-delta
        for i in range(blasts.size()-1,-1,-1):
            if float(blasts[i].life)<=0.0: blasts.remove_at(i)
        queue_redraw()

    func launch(enemy_side: bool=false, amount: float=100.0) -> void:
        var start: Vector2=Vector2(size.x*0.79,size.y*0.53) if not enemy_side else Vector2(size.x*0.21,size.y*0.53)
        var target: Vector2=Vector2(size.x*0.50,size.y*0.53)
        var count: int=clampi(int(ceil(amount/100.0)),1,28)
        for i in range(count): movers.append({"enemy":enemy_side,"from":start+Vector2(randf_range(-25,25),randf_range(-45,45)),"to":target+Vector2(randf_range(-45,45),randf_range(-55,55)),"t":-i*0.025,"speed":randf_range(0.45,0.75)})

    func explode() -> void:
        blasts.append({"p":Vector2(size.x*0.5,size.y*0.53)+Vector2(randf_range(-60,60),randf_range(-70,70)),"life":0.5})

    func _gui_input(e: InputEvent) -> void:
        var pos:=Vector2.ZERO; var down:=false; var up:=false; var move:=false
        if e is InputEventScreenTouch: pos=e.position; down=e.pressed; up=not e.pressed
        elif e is InputEventScreenDrag: pos=e.position; move=true
        elif e is InputEventMouseButton and e.button_index==MOUSE_BUTTON_LEFT: pos=e.position; down=e.pressed; up=not e.pressed
        elif e is InputEventMouseMotion and dragging: pos=e.position; move=true
        else: return
        var home:=Rect2(size.x*0.68,size.y*0.20,size.x*0.29,size.y*0.64)
        var enemy:=Rect2(size.x*0.03,size.y*0.20,size.x*0.29,size.y*0.64)
        if down and home.has_point(pos) and our_reserve>0.0: dragging=true; drag_from=home.get_center(); drag_to=pos
        elif move and dragging: drag_to=pos
        elif up and dragging:
            if enemy.has_point(pos) or pos.x<size.x*0.62:
                var dist: float=drag_from.distance_to(pos)
                var share: float=0.25 if dist<size.x*0.35 else (0.5 if dist<size.x*0.55 else 1.0)
                send_army.emit(share)
            dragging=false
        queue_redraw(); accept_event()

    func _draw() -> void:
        var w:=size.x; var h:=size.y
        draw_rect(Rect2(Vector2.ZERO,size),Color("14252e"))
        var left:=Rect2(w*0.03,h*0.20,w*0.29,h*0.64); var right:=Rect2(w*0.68,h*0.20,w*0.29,h*0.64)
        _country(left,enemy_flag,enemy_name,enemy_reserve,Color("8b3030")); _country(right,our_flag,our_name,our_reserve,Color("245f43"))
        draw_string(ThemeDB.fallback_font,Vector2(w*0.34,h*0.12),"ФРОНТ",HORIZONTAL_ALIGNMENT_CENTER,w*0.32,22,Color.WHITE)
        draw_string(ThemeDB.fallback_font,Vector2(w*0.32,h*0.91),"%s %s   ⚔   %s %s"%[enemy_flag,_num(enemy_column),our_flag,_num(our_column)],HORIZONTAL_ALIGNMENT_CENTER,w*0.36,19,Color.WHITE)
        for m in movers:
            var t: float=clampf(float(m.t),0.0,1.0); var p: Vector2=Vector2(m.from).lerp(Vector2(m.to),t); _rocket_person(p,bool(m.enemy))
        for b in blasts: draw_circle(Vector2(b.p),12.0+30.0*float(b.life),Color(1.0,0.55,0.12,0.6))
        if dragging: draw_line(drag_from,drag_to,Color("fff09a"),7.0,true)

    func _country(r:Rect2,flag:String,title:String,reserve:float,tint:Color)->void:
        var poly:=PackedVector2Array([r.position+Vector2(r.size.x*0.12,r.size.y*0.22),r.position+Vector2(r.size.x*0.38,r.size.y*0.05),r.position+Vector2(r.size.x*0.82,r.size.y*0.17),r.position+Vector2(r.size.x*0.94,r.size.y*0.48),r.position+Vector2(r.size.x*0.75,r.size.y*0.86),r.position+Vector2(r.size.x*0.32,r.size.y*0.94),r.position+Vector2(r.size.x*0.06,r.size.y*0.65)])
        draw_colored_polygon(poly,tint); draw_polyline(poly,Color.WHITE,3.0,true)
        draw_string(ThemeDB.fallback_font,r.position+Vector2(0,r.size.y*0.43),flag,HORIZONTAL_ALIGNMENT_CENTER,r.size.x,42,Color.WHITE)
        draw_string(ThemeDB.fallback_font,r.position+Vector2(0,r.size.y*0.57),title,HORIZONTAL_ALIGNMENT_CENTER,r.size.x,22,Color.WHITE)
        draw_string(ThemeDB.fallback_font,r.position+Vector2(0,r.size.y*0.69),"Армия: %s"%_num(reserve),HORIZONTAL_ALIGNMENT_CENTER,r.size.x,20,Color.WHITE)

    func _rocket_person(p:Vector2,enemy:bool)->void:
        var dir: float=1.0 if enemy else -1.0
        var body:=PackedVector2Array([p+Vector2(-9*dir,-4),p+Vector2(5*dir,-4),p+Vector2(12*dir,0),p+Vector2(5*dir,4),p+Vector2(-9*dir,4)])
        draw_colored_polygon(body,Color("ff6b62") if enemy else Color("72ffa5")); draw_line(p+Vector2(-10*dir,0),p+Vector2(-18*dir,0),Color("ffcf55"),4.0)

    func _num(v:float)->String:
        if v>=1000000.0:return "%.2f млн"%(v/1000000.0)
        if v>=1000.0:return "%.0f тыс"%(v/1000.0)
        return "%.0f"%v

func _resolve_battle(attacker_id:String,defender_id:String,attack_fraction:float=1.0,silent_bot:bool=false)->void:
    if attacker_id!=player_id and defender_id!=player_id:
        super._resolve_battle(attacker_id,defender_id,attack_fraction,silent_bot); return
    if tactical_active or _are_allies(attacker_id,defender_id): return
    _start_tactical_battle(attacker_id,defender_id)

func _open_attack_dialog(target:String)->void:
    if target==player_id or _are_allies(player_id,target):return
    _start_tactical_battle(player_id,target)

func _start_tactical_battle(attacker_id:String,defender_id:String)->void:
    if tactical_active:return
    tactical_active=true; var old_pause:bool=paused; paused=true
    var ps:String=player_id; var es:String=defender_id if attacker_id==player_id else attacker_id
    var p:Dictionary=countries[ps]; var e:Dictionary=countries[es]
    var our_start:float=float(p.get("army",0.0)); var enemy_start:float=float(e.get("army",0.0))
    var our_reserve:Array=[our_start]; var enemy_reserve:Array=[enemy_start]; var our_column:Array=[0.0]; var enemy_column:Array=[0.0]
    var overlay:=ColorRect.new(); overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); overlay.color=Color("071922"); overlay.z_index=800; overlay.mouse_filter=Control.MOUSE_FILTER_STOP; add_child(overlay)
    var root:=VBoxContainer.new(); root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.offset_left=8; root.offset_right=-8; root.offset_top=8; root.offset_bottom=-8; overlay.add_child(root)
    var title:=Label.new(); title.text="%s  против  %s"%[p.name,e.name]; title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; title.add_theme_font_size_override("font_size",22); root.add_child(title)
    var front:=BattleFront.new(); front.size_flags_vertical=Control.SIZE_EXPAND_FILL; front.custom_minimum_size=Vector2(700,440); front.our_name=str(p.name); front.enemy_name=str(e.name); front.our_flag=str(FLAGS.get(ps,"🏳️")); front.enemy_flag=str(FLAGS.get(es,"🏳️")); root.add_child(front)
    front.send_army.connect(func(share:float):
        var amount:float=float(our_reserve[0])*share
        if amount>0.0: our_reserve[0]=float(our_reserve[0])-amount; our_column[0]=float(our_column[0])+amount; front.launch(false,amount)
    )
    var retreat:=Button.new(); retreat.text="ОТСТУПИТЬ"; retreat.custom_minimum_size.y=58; root.add_child(retreat)
    var retreating:Array=[false]; retreat.pressed.connect(func():retreating[0]=true)
    var ai_clock:float=0.0
    while not bool(retreating[0]) and is_instance_valid(overlay):
        await get_tree().create_timer(0.20,true,false,true).timeout; ai_clock+=0.20
        if ai_clock>=0.8:
            ai_clock=0.0
            if float(enemy_reserve[0])>0.0:
                var amount:float=minf(float(enemy_reserve[0]),maxf(enemy_start*randf_range(0.025,0.07),100.0)); enemy_reserve[0]=float(enemy_reserve[0])-amount; enemy_column[0]=float(enemy_column[0])+amount; front.launch(true,amount)
        if float(our_column[0])>0.0 and float(enemy_column[0])>0.0:
            var op:float=float(our_column[0]); var ep:float=float(enemy_column[0]); our_column[0]=maxf(0.0,op-ep*randf_range(0.002,0.004)); enemy_column[0]=maxf(0.0,ep-op*randf_range(0.002,0.004)); if randf()<0.45:front.explode()
        elif float(our_column[0])>0.0 and float(enemy_reserve[0])>0.0:
            var hit:float=minf(float(enemy_reserve[0]),float(our_column[0])*randf_range(0.0015,0.003)); enemy_reserve[0]=float(enemy_reserve[0])-hit
        elif float(enemy_column[0])>0.0 and float(our_reserve[0])>0.0:
            var hit:float=minf(float(our_reserve[0]),float(enemy_column[0])*randf_range(0.0015,0.003)); our_reserve[0]=float(our_reserve[0])-hit
        front.our_reserve=float(our_reserve[0]); front.enemy_reserve=float(enemy_reserve[0]); front.our_column=float(our_column[0]); front.enemy_column=float(enemy_column[0]); front.queue_redraw()
        if float(enemy_reserve[0])<=0.0 and float(enemy_column[0])<=0.0:break
        if float(our_reserve[0])<=0.0 and float(our_column[0])<=0.0:break
    var did_retreat:bool=bool(retreating[0]); if is_instance_valid(overlay):overlay.queue_free()
    var our_survivors:float=float(our_reserve[0])+float(our_column[0]); var enemy_survivors:float=float(enemy_reserve[0])+float(enemy_column[0])
    var our_loss:float=maxf(0.0,our_start-our_survivors); var enemy_loss:float=maxf(0.0,enemy_start-enemy_survivors)
    p.army=our_survivors; e.army=enemy_survivors
    p.population=maxf(0.1,float(p.population)-our_loss/1000000.0); e.population=maxf(0.1,float(e.population)-enemy_loss/1000000.0)
    p.war_fatigue=minf(100.0,float(p.war_fatigue)+5.0); e.war_fatigue=minf(100.0,float(e.war_fatigue)+5.0); p.relations[es]=-100; e.relations[ps]=-100
    if did_retreat:_push_news("%s отступает. Потери сохранены."%p.name)
    else:
        var winner:String=ps if our_survivors>enemy_survivors else es; _push_news("БИТВА: %s - %s: победа %s."%[countries[attacker_id].name,countries[defender_id].name,countries[winner].name])
    _mark_activity(attacker_id,ACTIVITY_WAR,6); _mark_activity(defender_id,ACTIVITY_WAR,6); paused=old_pause; tactical_active=false; _refresh_all()
