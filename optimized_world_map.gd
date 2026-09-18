extends "res://world_map.gd"

const UNIT_SPACING := 9.0
const UNIT_RADIUS := 3.2
const MAX_VISIBLE_UNITS := 90
const FIELD_KILL_INTERVAL := 0.075
const ARRIVAL_KILL_INTERVAL := 0.055
const EMIT_INTERVAL := UNIT_SPACING / ARMY_SPEED

var field_combat_clock:Dictionary={}

func _safe_anchor(poly:PackedVector2Array)->Vector2:
    if poly.size()<3:return Vector2.ZERO
    var bb:Rect2=_bounds(poly);var center:Vector2=bb.get_center()
    if Geometry2D.is_point_in_polygon(center,poly):return center
    var best:Vector2=poly[0];var best_distance:float=INF
    for gy in range(1,8):
        for gx in range(1,8):
            var p:Vector2=bb.position+Vector2(bb.size.x*float(gx)/8.0,bb.size.y*float(gy)/8.0)
            if not Geometry2D.is_point_in_polygon(p,poly):continue
            var distance:float=p.distance_squared_to(center)
            if distance<best_distance:best_distance=distance;best=p
    return best

func _army_direction(a:Dictionary)->Vector2:
    var target:String=str(a.target)
    if feature_centers.has(target):
        var d:Vector2=Vector2(feature_centers[target])-Vector2(a.pos)
        if d.length_squared()>0.01:return d.normalized()
    return Vector2.RIGHT

func _army_tail(a:Dictionary)->Vector2:
    var visible:int=mini(int(float(a.amount)),MAX_VISIBLE_UNITS)
    return Vector2(a.pos)-_army_direction(a)*UNIT_SPACING*float(maxi(0,visible-1))

func _draw_army(center:Vector2,amount:int,owner:String,direction:Vector2)->void:
    if amount<=0:return
    var visible:int=mini(amount,MAX_VISIBLE_UNITS)
    var color:Color=_owner_color(owner)
    var side:Vector2=Vector2(-direction.y,direction.x)
    for i in range(visible):
        var p:Vector2=center-direction*(float(i)*UNIT_SPACING)
        draw_circle(p,UNIT_RADIUS+2.0,Color(color.r,color.g,color.b,0.10))
        draw_circle(p,UNIT_RADIUS,Color(color.r,color.g,color.b,0.96))
    draw_string_outline(ThemeDB.fallback_font,center+side*12.0+Vector2(-24,-18),str(amount),HORIZONTAL_ALIGNMENT_CENTER,48,14,3,Color(0,0,0,0.92))
    draw_string(ThemeDB.fallback_font,center+side*12.0+Vector2(-24,-18),str(amount),HORIZONTAL_ALIGNMENT_CENTER,48,14,Color.WHITE)

func _segments_touch(a:Dictionary,b:Dictionary)->bool:
    var a0:Vector2=Vector2(a.pos);var a1:Vector2=_army_tail(a);var b0:Vector2=Vector2(b.pos);var b1:Vector2=_army_tail(b)
    var crossing:Variant=Geometry2D.segment_intersects_segment(a0,a1,b0,b1)
    if crossing!=null:return true
    var limit_sq:float=(UNIT_RADIUS*2.4)*(UNIT_RADIUS*2.4)
    return _segment_distance_squared(a0,b0,b1)<=limit_sq or _segment_distance_squared(a1,b0,b1)<=limit_sq or _segment_distance_squared(b0,a0,a1)<=limit_sq or _segment_distance_squared(b1,a0,a1)<=limit_sq

func _collision_point(a:Dictionary,b:Dictionary)->Vector2:
    var a0:Vector2=Vector2(a.pos);var a1:Vector2=_army_tail(a);var b0:Vector2=Vector2(b.pos);var b1:Vector2=_army_tail(b);var crossing:Variant=Geometry2D.segment_intersects_segment(a0,a1,b0,b1)
    if crossing is Vector2:return Vector2(crossing)
    return (a0+b0)*0.5


func _reserved_from(source_iso:String)->float:
    var total:float=0.0
    for a in armies:
        if str(a.get("source",""))==source_iso:
            total+=float(a.get("pending",0.0))
    return total

func _send_army(from_iso:String,to_iso:String,share:=0.5,ai:=false)->void:
    if game_over or not PLAYABLE_IDS.has(from_iso) or not PLAYABLE_IDS.has(to_iso) or from_iso==to_iso or not territories.has(from_iso) or not territories.has(to_iso):return
    var src:Dictionary=territories[from_iso]
    if str(src.owner)=="NEUTRAL" or (not ai and str(src.owner)!=player_country):return
    var free:float=maxf(0.0,float(src.army)-_reserved_from(from_iso))
    var requested:float=floor(free*share)
    if requested<1.0 or not feature_centers.has(from_iso):return
    armies.append({"owner":str(src.owner),"amount":0.0,"pending":requested,"emit_clock":EMIT_INTERVAL,"source":from_iso,"pos":Vector2(feature_centers[from_iso]),"target":to_iso})

func _send_amount(from_iso:String,to_iso:String,amount:float)->void:
    if not territories.has(from_iso):return
    var free:float=maxf(0.0,float(territories[from_iso].army)-_reserved_from(from_iso)-AI_RESERVE)
    var send:float=minf(floor(amount),floor(free))
    if send<1.0:return
    _send_army(from_iso,to_iso,send/maxf(1.0,float(territories[from_iso].army)-_reserved_from(from_iso)),true)

func _projected_at(owner:String,target_iso:String)->float:
    var total:float=0.0
    for a in armies:
        if str(a.owner)==owner and str(a.target)==target_iso:
            total+=float(a.amount)+float(a.get("pending",0.0))
    return total

func _emit_units(a:Dictionary,delta:float)->void:
    var pending:int=int(float(a.get("pending",0.0)))
    if pending<=0:return
    var source:String=str(a.get("source",""))
    if not territories.has(source) or str(territories[source].owner)!=str(a.owner):
        a["pending"]=0.0
        return
    a["emit_clock"]=float(a.get("emit_clock",0.0))+delta
    while float(a["emit_clock"])>=EMIT_INTERVAL and int(float(a.get("pending",0.0)))>0:
        if float(territories[source].army)<1.0:
            a["pending"]=0.0
            break
        a["emit_clock"]=float(a["emit_clock"])-EMIT_INTERVAL
        territories[source].army=float(territories[source].army)-1.0
        a.amount=float(a.amount)+1.0
        a["pending"]=float(a["pending"])-1.0

func _move_armies(delta:float)->void:
    for i in range(armies.size()-1,-1,-1):
        if i>=armies.size():continue
        var a:Dictionary=armies[i];var target:String=str(a.target)
        if not PLAYABLE_IDS.has(target) or not feature_centers.has(target):armies.remove_at(i);continue
        _emit_units(a,delta)
        if float(a.amount)<=0.0:continue
        var dest:Vector2=Vector2(feature_centers[target]);var pos:Vector2=Vector2(a.pos)
        if pos.distance_to(dest)<=ARMY_SPEED*delta:
            a.pos=dest;a["arrival_clock"]=float(a.get("arrival_clock",0.0))+delta;_resolve_arrival_stream(i)
        else:a.pos=pos.move_toward(dest,ARMY_SPEED*delta)
    _resolve_line_collisions(delta)

func _resolve_arrival_stream(index:int)->void:
    if index<0 or index>=armies.size():return
    var a:Dictionary=armies[index]
    if float(a.get("arrival_clock",0.0))<ARRIVAL_KILL_INTERVAL:return
    a["arrival_clock"]=float(a.get("arrival_clock",0.0))-ARRIVAL_KILL_INTERVAL
    var target:String=str(a.target)
    if not territories.has(target):armies.remove_at(index);return
    var t:Dictionary=territories[target];var owner:String=str(a.owner)
    a.amount=float(a.amount)-1.0
    if str(t.owner)==owner:
        t.army=float(t.army)+1.0
    elif float(t.army)>0.0:
        t.army=maxf(0.0,float(t.army)-1.0)
        collision_flashes.append({"pos":Vector2(a.pos),"life":0.18})
    else:
        t.owner=owner;t.army=1.0
    if float(a.amount)<=0.0 and float(a.get("pending",0.0))<=0.0:armies.remove_at(index)
    _check_end_state()

func _resolve_line_collisions(delta:float)->void:
    var active_keys:Dictionary={};var i:int=0
    while i<armies.size():
        var j:int=i+1
        while j<armies.size():
            if str(armies[i].owner)!=str(armies[j].owner) and _segments_touch(armies[i],armies[j]):
                var key:String=str(i)+":"+str(j)
                active_keys[key]=true;field_combat_clock[key]=float(field_combat_clock.get(key,0.0))+delta
                if float(field_combat_clock[key])>=FIELD_KILL_INTERVAL:
                    field_combat_clock[key]=float(field_combat_clock[key])-FIELD_KILL_INTERVAL;armies[i].amount=float(armies[i].amount)-1.0;armies[j].amount=float(armies[j].amount)-1.0;collision_flashes.append({"pos":_collision_point(armies[i],armies[j]),"life":0.16})
                    if float(armies[j].amount)<=0.0:armies.remove_at(j);continue
                    if float(armies[i].amount)<=0.0:armies.remove_at(i);i-=1;break
            j+=1
        i+=1
    for key in field_combat_clock.keys():
        if not active_keys.has(key):field_combat_clock.erase(key)