extends RefCounted
const WEATHER = {"clear":{"name":"晴天","distance":360.0},"rain":{"name":"雨天","distance":190.0},"fog":{"name":"雾天","distance":85.0}}
static func in_distance(observer:Vector3,target:Vector3,weather:String)->bool:
	return observer.distance_to(target)<=WEATHER.get(weather,WEATHER.fog).distance
static func segment_sphere(a:Vector3,b:Vector3,center:Vector3,radius:float)->bool:
	var ab:=b-a
	var t:float=clampf((center-a).dot(ab)/maxf(ab.length_squared(),.000001),0,1)
	return (a+ab*t).distance_to(center)<=radius
static func reason(observer:Vector3,target:Vector3,weather:String,smoke_center:Vector3,smoke_active:bool,blocked:bool,smoke_radius:float=6.5)->String:
	if not in_distance(observer,target,weather):return "range"
	if smoke_active and smoke_radius>0.0 and segment_sphere(observer,target,smoke_center,smoke_radius):return "smoke"
	if blocked:return "obstacle"
	return "visible"
