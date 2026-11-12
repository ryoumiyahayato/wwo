extends RefCounted
## Admission and completion run on the main thread. Workers own only their inputs and result.

const FOUNDATION: int = 0
const VISIBLE: int = 1
const OPTIONAL: int = 2
const MAX_QUEUED: int = 24
const MAX_NATIVE: int = 8

class Job extends RefCounted:
	var work: Callable
	var label: String
	var priority: int
	var owner: RefCounted
	var task_id: int = -1
	var completed: bool
	var result: Variant
	var measured: bool
	var worker_usec: int
	var _mutex := Mutex.new()
	var _abandoned: bool

	func run() -> void:
		var began := Time.get_ticks_usec() if measured else 0
		var value: Variant = work.call()
		if began>0: worker_usec = Time.get_ticks_usec()-began
		_mutex.lock()
		if not _abandoned: result = value
		_mutex.unlock()

	func discard() -> void:
		_mutex.lock()
		_abandoned = true
		var discarded: Variant = result
		result = null
		_mutex.unlock()
		discarded = null

	func take() -> Variant:
		assert(completed)
		var value: Variant = result
		result = null
		return value

static var _queued: Array[Job] = []
static var _active: Array[Job] = []
static var _native: Dictionary[String,bool] = {}
static var _limit: int = 0
static var peak_running: int = 0
static var peak_cpu_jobs: int = 0
static var measuring: bool = false
static var measured_jobs: Dictionary = {}
static var reap_usec: int

static func limit() -> int:
	if _limit>0: return _limit
	var processors := OS.get_processor_count()
	_limit = 1 if processors<8 else 2
	if OS.is_debug_build():
		var override := OS.get_environment("WWO_MAP_WORKERS")
		if override.is_valid_int(): _limit = clampi(override.to_int(),1,clampi(processors-2,1,4))
	return _limit

static func submit(work: Callable, label: String, priority: int, owner: RefCounted = null) -> Job:
	if _queued.size()>=MAX_QUEUED: return null
	var job := Job.new()
	job.work = work
	job.label = label
	job.priority = priority
	job.owner = owner
	job.measured = measuring
	var position := _queued.size()
	while position>0 and _queued[position-1].priority>priority: position -= 1
	_queued.insert(position,job)
	_watch()
	return job

static func cancel_queued(job: Job) -> void:
	if job==null or job.completed or job.task_id>=0: return
	_queued.erase(job)
	_finish(job)

static func abandon(job: Job) -> void:
	if job==null: return
	job.discard()
	cancel_queued(job)

static func request_resource(path: String, type: String = "", cache: ResourceLoader.CacheMode = ResourceLoader.CACHE_MODE_REUSE) -> Error:
	if _native.has(path) or _native.size()>=MAX_NATIVE or not _queued.is_empty(): return ERR_BUSY
	var running := _active.size()+_native_running()
	if running>=limit(): return ERR_BUSY
	var error := ResourceLoader.load_threaded_request(path,type,false,cache)
	if error==OK:
		_native[path] = false
		peak_running = maxi(peak_running,running+1)
		_watch()
	return error

static func take_resource(path: String) -> Resource:
	var status := ResourceLoader.load_threaded_get_status(path)
	if status==ResourceLoader.THREAD_LOAD_IN_PROGRESS: return null
	_native.erase(path)
	if status==ResourceLoader.THREAD_LOAD_INVALID_RESOURCE: return null
	return ResourceLoader.load_threaded_get(path)

static func abandon_resource(path: String) -> void:
	if _native.has(path): _native[path] = true

static func _watch() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree.process_frame.is_connected(_pump): tree.process_frame.connect(_pump)

static func _native_running() -> int:
	var count := 0
	for path: String in _native:
		if ResourceLoader.load_threaded_get_status(path)==ResourceLoader.THREAD_LOAD_IN_PROGRESS: count += 1
	return count

static func _pump() -> void:
	for i: int in range(_active.size()-1,-1,-1):
		var job := _active[i]
		if not WorkerThreadPool.is_task_completed(job.task_id): continue
		# Godot requires reaping completed IDs. This path never waits on live work.
		var began := Time.get_ticks_usec() if job.measured else 0
		WorkerThreadPool.wait_for_task_completion(job.task_id)
		if began>0:
			reap_usec = maxi(reap_usec,Time.get_ticks_usec()-began)
			var row: Array = measured_jobs.get(job.label,[0,0,0])
			row[0] += 1
			row[1] += job.worker_usec
			row[2] = maxi(row[2],job.worker_usec)
			measured_jobs[job.label] = row
		_active.remove_at(i)
		_finish(job)
	for path: String in _native.keys():
		if _native[path]: take_resource(path)
	# Completed native resources can await a view's upload budget while it is hidden.
	var native_running := _native_running()
	while not _queued.is_empty() and _active.size()+native_running<limit():
		var job: Job = _queued.pop_front()
		job.task_id = WorkerThreadPool.add_task(job.run,job.priority==FOUNDATION,job.label)
		_active.append(job)
		peak_cpu_jobs = maxi(peak_cpu_jobs,_active.size())
		peak_running = maxi(peak_running,_active.size()+native_running)
	if _queued.is_empty() and _active.is_empty() and _native.is_empty():
		(Engine.get_main_loop() as SceneTree).process_frame.disconnect(_pump)

static func _finish(job: Job) -> void:
	job.completed = true
	job.work = Callable()
	job.owner = null
