extends "res://main_game_tuning.gd"

# One-field real-time battle: troops control the field, missiles are expendable strikes.
var tactical_active := false

class BattleField:
    extends Control
    signal send_troops(share)
    signal send_missiles(share)
    var our_reserve:=0.0
    var our_missiles:=0.0
    var enemy_reserve:=0.0
    var enemy_missiles:=0.0
    var our_field:=0.0
    var enemy_field:=0.0
    var our_flag:="🇷🇺"
    var enemy_flag:="🏳️"
    var dragging:=""
    var drag_from:=Vector2.ZERO
    var drag_to:=Vector2.ZERO
    var movers:=[]
    var blasts:=[]

    func _process(delta:float)->void:
        for m in movers: m.t=float(m.t)+delta*float(m.speed)
        for i in range(movers.size()-1,-1,-1):
            if float(movers[i].t)>=1.0:movers.remove_at(i)
        for b in blasts:b.life=float(b.life)-delta
        for i in range(blasts.size()-1,-1,-1):
            if float(blasts[i].life)<=0:blasts.remove_at(i)
        queue_redraw()

    func launch(kind:String,enemy_side:bool=false)->void:
        var start:=Vector2(size.x-100,size.y*(0.38 if kind=="troops" else 0.68)) if enemy_side else Vector2(100,size.y*(0.38 if kind=="troops" else 0.68))
        var target:=Vector2(size.x*0.5,size.y*0.5)
        var n:=12 if kind=="troops" else 5
        for i in range(n):movers.append({"kind":kind,"enemy":enemy_side,"from":start+Vector2(randf_range(-20,20),randf_range(-15,15)),"to":target+Vector2(randf_range(-55,55),randf_range(-45,45)),"t":-i*0.045,"speed":randf_range(0.65,1.05)})
    func explode()->void:
        for i in range(4):blasts.append({"p":Vector2(size.x*0.5,size.y*0.5)+Vector2(randf_range(-70,70),randf_range(-55,55)),"life":0.45})

    func _gui_input(e:InputEvent)->void:
        var p:=Vector2.ZERO;var down:=false;var up:=false;var move:=false
        if e is InputEventScreenTouch:p=e.position;down=e.pressed;up=not e.pressed
        elif e is InputEventScreenDrag:p=e.position;move=true
        elif e is InputEventMouseButton and e.button_index==MOUSE_BUTTON_LEFT:p=e.position;down=e.pressed;up=not e.pressed
        elif e is InputEventMouseMotion and dragging!="":p=e.position;move=true
        else:return
        var tr:=Rect2(18,size.y*0.24,size.x*0.20,size.y*0.25);var mr:=Rect2(18,size.y*0.58,size.x*0.20,size.y*0.20);var battlefield:=Rect2(size.x*0.29,size.y*0.17,size.x*0.42,size.y*0.66)
        if down:
            if tr.has_point(p) and our_reserve>0:dragging="troops";drag_from=tr.get_center();drag_to=p
            elif mr.has_point(p) and our_missiles>0:dragging="missiles";drag_from=mr.get_center();drag_to=p
        elif move and dragging!="":drag_to=p
        elif up and dragging!="":
            if battlefield.has_point(p):
                var dist:=drag_from.distance_to(p);var share:=0.25 if dist<size.x*0.40 else (0.5 if dist<size.x*0.55 else 1.0)
                if dragging=="troops":send_troops.emit(share)
                else:send_missiles.emit(share)
            dragging=""
        queue_redraw();accept_event()

    func _draw()->void:
        var w:=size.x;var h:=size.y
        draw_rect(Rect2(Vector2.ZERO,size),Color("174936"))
        for i in range(10):draw_line(Vector2(0,h*i/9.0),Vector2(w,h*i/9.0),Color(0.2,0.55,0.3,0.18),2)
        var tr:=Rect2(18,h*0.24,w*0.20,h*0.25);var mr:=Rect2(18,h*0.58,w*0.20,h*0.20);var er:=Rect2(w*0.78,h*0.24,w*0.20,h*0.25);var em:=Rect2(w*0.78,h*0.58,w*0.20,h*0.20);var bf:=Rect2(w*0.29,h*0.17,w*0.42,h*0.66)
        _panel(tr,Color("3ddc84"),Color(0.03,0.15,0.09,0.92));_panel(mr,Color("ffcf4a"),Color(0.17,0.12,0.03,0.92));_panel(er,Color("ff655b"),Color(0.20,0.04,0.04,0.92));_panel(em,Color("ff9b45"),Color(0.20,0.08,0.03,0.92))
        draw_string(ThemeDB.fallback_font,tr.position+Vector2(12,28),"■ ВОЙСКА",0,-1,18,Color.WHITE);draw_string(ThemeDB.fallback_font,tr.position+Vector2(12,58),_num(our_reserve),0,-1,24,Color("65ff9e"))
        draw_string(ThemeDB.fallback_font,mr.position+Vector2(12,28),"● РАКЕТЫ",0,-1,18,Color.WHITE);draw_string(ThemeDB.fallback_font,mr.position+Vector2(12,58),_num(our_missiles),0,-1,24,Color("ffe27a"))
        draw_string(ThemeDB.fallback_font,er.position+Vector2(12,28),"ВОЙСКА ■",0,-1,18,Color.WHITE);draw_string(ThemeDB.fallback_font,er.position+Vector2(12,58),_num(enemy_reserve),0,-1,24,Color("ff8c84"))
        draw_string(ThemeDB.fallback_font,em.position+Vector2(12,28),"РАКЕТЫ ●",0,-1,18,Color.WHITE);draw_string(ThemeDB.fallback_font,em.position+Vector2(12,58),_num(enemy_missiles),0,-1,24,Color("ffb474"))
        var control:=our_field-enemy_field;var bg:=Color(0.12,0.14,0.15,0.94)
        if control>1:bg=Color(0.05,0.25,0.12,0.94)
        elif control<-1:bg=Color(0.30,0.06,0.05,0.94)
        _panel(bf,Color("e6edf3"),bg)
        draw_string(ThemeDB.fallback_font,bf.position+Vector2(0,32),"ПОЛЕ БОЯ",HORIZONTAL_ALIGNMENT_CENTER,bf.size.x,22,Color.WHITE)
        var text:="НЕЙТРАЛЬНО\n0"
        var col:=Color("d8dee4")
        if our_field>0 and enemy_field>0:text="%s %s   ⚔   %s %s"%[our_flag,_num(our_field),enemy_flag,_num(enemy_field)];col=Color("fff0a6")
        elif our_field>0:text="%s  %s"%[our_flag,_num(our_field)];col=Color("65ff9e")
        elif enemy_field>0:text="%s  %s"%[enemy_flag,_num(enemy_field)];col=Color("ff8c84")
        draw_string(ThemeDB.fallback_font,bf.position+Vector2(0,bf.size.y*0.55),text,HORIZONTAL_ALIGNMENT_CENTER,bf.size.x,28,col)
        for m in movers:
            var t:=clampf(float(m.t),0,1);var p:Vector2=Vector2(m.from).lerp(Vector2(m.to),t);var c:=Color("ff655b") if bool(m.enemy) else Color("65ff9e")
            if str(m.kind)=="troops":draw_rect(Rect2(p-Vector2(5,5),Vector2(10,10)),c)
            else:draw_circle(p,5,Color("ffcf4a"));draw_line(p+Vector2(-15,0),p+Vector2(-5,0),Color(1,0.4,0.1,0.8),3)
        for b in blasts:draw_circle(Vector2(b.p),10+35*float(b.life),Color(1,0.55,0.1,0.55));draw_circle(Vector2(b.p),8+15*float(b.life),Color(1,0.95,0.5,0.9))
        if dragging!="":draw_line(drag_from,drag_to,Color("fff08a"),7,true)
    func _panel(r:Rect2,border:Color,bg:Color)->void:
        var s:=StyleBoxFlat.new();s.bg_color=bg;s.border_color=border;s.set_border_width_all(3);s.set_corner_radius_all(14);draw_style_box(s,r)
    func _num(v:float)->String:
        if v>=1000000:return "%.2f млн"%(v/1000000)
        if v>=1000:return "%.0f тыс"%(v/1000)
        return "%.0f"%v

func _resolve_battle(attacker_id:String,defender_id:String,attack_fraction:float=1.0,silent_bot:bool=false)->void:
    if attacker_id!=player_id and defender_id!=player_id:super._resolve_battle(attacker_id,defender_id,attack_fraction,silent_bot);return
    if tactical_active or _are_allies(attacker_id,defender_id):return
    _start_tactical_battle(attacker_id,defender_id)

func _open_attack_dialog(target:String)->void:
    if target==player_id or _are_allies(player_id,target):return
    _start_tactical_battle(player_id,target)

func _start_tactical_battle(attacker_id:String,defender_id:String)->void:
    if tactical_active:return
    tactical_active=true;var old_pause:=paused;paused=true
    var ps:=player_id;var es:=defender_id if attacker_id==player_id else attacker_id
    var p:Dictionary=countries[ps];var e:Dictionary=countries[es]
    var our_start:=float(p.army)+float(p.air)+float(p.navy)+float(p.def);var enemy_start:=float(e.army)+float(e.air)+float(e.navy)+float(e.def)
    var our_reserve:=[our_start];var enemy_reserve:=[enemy_start];var our_missiles:=[float(p.missile)];var enemy_missiles:=[float(e.missile)];var our_field:=[0.0];var enemy_field:=[0.0]
    var overlay:=ColorRect.new();overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);overlay.color=Color("071922");overlay.z_index=800;overlay.mouse_filter=Control.MOUSE_FILTER_STOP;add_child(overlay)
    var root:=VBoxContainer.new();root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.offset_left=8;root.offset_right=-8;root.offset_top=8;root.offset_bottom=-8;overlay.add_child(root)
    var title:=Label.new();title.text="%s   ⚔   %s"%[p.name,e.name];title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;title.add_theme_font_size_override("font_size",22);root.add_child(title)
    var hint:=Label.new();hint.text="Тяни ВОЙСКА или РАКЕТЫ в центр. Дальность свайпа: 25% / 50% / 100%.";hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;root.add_child(hint)
    var field:=BattleField.new();field.size_flags_vertical=Control.SIZE_EXPAND_FILL;field.custom_minimum_size=Vector2(700,440);root.add_child(field)
    field.our_flag="🇷🇺";field.enemy_flag="🏳️";field.our_reserve=our_reserve[0];field.enemy_reserve=enemy_reserve[0];field.our_missiles=our_missiles[0];field.enemy_missiles=enemy_missiles[0]
    field.send_troops.connect(func(share:float):var n:=our_reserve[0]*share;if n>0:our_reserve[0]-=n;our_field[0]+=n;field.launch("troops"))
    field.send_missiles.connect(func(share:float):var n:=maxf(1.0,our_missiles[0]*share);n=minf(n,our_missiles[0]);if n>0:our_missiles[0]-=n;enemy_field[0]=maxf(0.0,enemy_field[0]-n*8.0);field.launch("missiles");field.explode())
    var status:=Label.new();status.text="Поле нейтрально. Вводи силы сам - предварительного выбора армии больше нет.";status.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;root.add_child(status)
    var retreat:=Button.new();retreat.text="ОТСТУПИТЬ";retreat.custom_minimum_size.y=58;root.add_child(retreat)
    var retreating:=[false];retreat.pressed.connect(func():retreating[0]=true)
    var ai_clock:=0.0
    while not retreating[0] and is_instance_valid(overlay):
        await get_tree().create_timer(0.20,true,false,true).timeout;ai_clock+=0.20
        if ai_clock>=0.8:
            ai_clock=0.0
            if enemy_reserve[0]>0:
                var n:=minf(enemy_reserve[0],maxf(enemy_start*randf_range(0.025,0.07),100.0));enemy_reserve[0]-=n;enemy_field[0]+=n;field.launch("troops",true)
            if enemy_missiles[0]>0 and our_field[0]>0 and randf()<0.22:
                var m:=minf(enemy_missiles[0],maxf(1.0,float(e.missile)*0.02));enemy_missiles[0]-=m;our_field[0]=maxf(0.0,our_field[0]-m*8.0);field.launch("missiles",true);field.explode()
        if our_field[0]>0 and enemy_field[0]>0:
            var op:=our_field[0];var ep:=enemy_field[0];our_field[0]=maxf(0.0,op-ep*randf_range(0.0018,0.0035));enemy_field[0]=maxf(0.0,ep-op*randf_range(0.0018,0.0035));if randf()<0.45:field.explode()
        field.our_reserve=our_reserve[0];field.enemy_reserve=enemy_reserve[0];field.our_missiles=our_missiles[0];field.enemy_missiles=enemy_missiles[0];field.our_field=our_field[0];field.enemy_field=enemy_field[0];field.queue_redraw()
        if enemy_reserve[0]<=0 and enemy_field[0]<=0:break
        if our_reserve[0]<=0 and our_field[0]<=0:break
    var did_retreat:=retreating[0]
    if is_instance_valid(overlay):overlay.queue_free()
    # Player losses are permanent. On retreat, all surviving enemy troops return to its reserve;
    # only enemy troops actually killed during combat remain lost.
    var our_survivors:=our_reserve[0]+our_field[0];var enemy_survivors:=enemy_reserve[0]+enemy_field[0]
    var our_loss:=maxf(0.0,our_start-our_survivors);var enemy_loss:=maxf(0.0,enemy_start-enemy_survivors)
    _apply_combined_troop_loss(p,our_loss);_apply_combined_troop_loss(e,enemy_loss)
    p.missile=our_missiles[0];e.missile=enemy_missiles[0]
    p.population=maxf(0.1,float(p.population)-our_loss/1000000.0);e.population=maxf(0.1,float(e.population)-enemy_loss/1000000.0)
    p.war_fatigue=minf(100.0,float(p.war_fatigue)+5.0);e.war_fatigue=minf(100.0,float(e.war_fatigue)+5.0);p.relations[es]=-100;e.relations[ps]=-100
    if did_retreat:_push_news("%s отступает из боя с %s. Потери сторон сохранены; уцелевшие силы противника вернулись из поля боя."%[p.name,e.name])
    else:
        var winner:=ps if our_survivors>enemy_survivors else es;_push_news("БИТВА: %s - %s: победа %s."%[countries[attacker_id].name,countries[defender_id].name,countries[winner].name])
    _mark_activity(attacker_id,ACTIVITY_WAR,6);_mark_activity(defender_id,ACTIVITY_WAR,6);paused=old_pause;tactical_active=false;_refresh_all()

func _apply_combined_troop_loss(c:Dictionary,loss:float)->void:
    var total:=float(c.army)+float(c.air)+float(c.navy)+float(c.def)
    if total<=0:return
    var ratio:=clampf(loss/total,0.0,1.0)
    for key in ["army","air","navy","def"]:c[key]=maxf(0.0,float(c[key])*(1.0-ratio))
