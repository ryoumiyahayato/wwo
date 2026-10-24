## Reused from economy-consumer-access-20261022/merchant/merchant_market_contacts.gd; value projection only.
extends RefCounted
## Value-only analysis. A relationship never creates a warehouse or a route.
const WINDOW_DAYS: int = 7

static func _node(nodes: Dictionary, id: String) -> Dictionary:
	if not nodes.has(id): nodes[id]={"place_id":id,"goods":{}}
	return nodes[id]

static func _activity(nodes: Dictionary, id: String, good: String) -> Dictionary:
	var node: Dictionary=_node(nodes,id)
	if not node.goods.has(good):node.goods[good]={"received":0,"sent":0,"local_received":0,"partners":[],"delivery_ids":[]}
	return node.goods[good]

static func project(own: Dictionary, received: Array[Dictionary], minute: int) -> Dictionary:
	var contacts: Array[Dictionary]=received.duplicate(true)
	var nodes: Dictionary={}
	var flows: Dictionary={}
	var links: Dictionary={}
	for operation: Dictionary in own.get("operations",[]):
		for fact: Dictionary in operation.get("supplier_introductions",[]):
			var key: String=str(fact.buyer_site)+"|"+str(fact.seller_site)+"|"+str(fact.good)
			var link: Dictionary=fact.duplicate(true)
			link["inventory_adaptation"]=operation.get("product_needs",{}).get(fact.good,{}).get("inventory_adaptation",{}).duplicate(true)
			link.merge({"can_order_one":null,"current_reasons":[],"quote_ids":[],"pending_responsibility":0,"transit_responsibility":0,"received_in_window":0,"all_time_received":0,"last_delivery_day":null,"receipt_count":0,"recent_order_ids":[]})
			links[key]=link
	for offer: Dictionary in contacts:
		var key: String=str(offer.buyer_site)+"|"+str(offer.seller_site)+"|"+str(offer.good)
		if not links.has(key):continue
		var link: Dictionary=links[key]
		if offer.get("can_order_one") is bool:
			link.can_order_one=bool(link.can_order_one) or bool(offer.can_order_one)
		var why: String=str(offer.get("order_reason",offer.get("reason","UNKNOWN")))
		if why not in link.current_reasons:link.current_reasons.append(why)
		if offer.get("published_quote_id","") not in link.quote_ids:link.quote_ids.append(offer.get("published_quote_id",""))
	var seen: Dictionary={}
	var day: int=minute/1440
	var start: int=maxi(0,day-WINDOW_DAYS+1)
	for row: Dictionary in contacts:
		_node(nodes,str(row.from_place_id));_node(nodes,str(row.to_place_id))
	var orders: Array=[]
	orders.append_array(own.get("orders",[]));orders.append_array(own.get("sales_orders",[]))
	for order: Dictionary in orders:
		var id: String=str(order.get("id",""))
		if id.is_empty() or seen.has(id):continue
		seen[id]=true
		var origin: String=str(order.get("from_place_id",""))
		var destination: String=str(order.get("to_place_id",""))
		if origin.is_empty() or destination.is_empty():continue
		_node(nodes,origin);_node(nodes,destination)
		var good: String=str(order.good)
		var link_key: String=str(order.get("buyer_site",""))+"|"+str(order.get("seller_site",""))+"|"+good
		var link: Dictionary=links.get(link_key,{})
		if not link.is_empty():
			link.pending_responsibility+=int(order.get("pending",0));link.transit_responsibility+=int(order.get("transit",0))
			link.all_time_received+=int(order.get("delivered",0))
			if int(order.get("accepted_day",-1))>=start:link.recent_order_ids.append(id)
		var key: String=origin+"|"+destination+"|"+good
		if not flows.has(key):flows[key]={"from_place_id":origin,"to_place_id":destination,"good":good,"received_in_window":0,"order_ids":[],"delivery_ids":[],"last_delivery_day":null,"receipt_count":0,"lead_quantity":0,"lead_quantity_days":0,"minimum_lead_days":null,"maximum_lead_days":null}
		var flow: Dictionary=flows[key]
		flow.order_ids.append(id)
		for delivery: Dictionary in order.get("deliveries",[]):
			var at: int=int(delivery.get("delivered_day",-1))
			if not link.is_empty() and int(delivery.get("quantity",0))>0 and at<=day:
				link.last_delivery_day=at if link.last_delivery_day==null else maxi(at,int(link.last_delivery_day))
			if at<start or at>day:continue
			var quantity: int=int(delivery.get("quantity",0))
			if quantity<=0:continue
			var reference: String=str(delivery.get("id",""))
			flow.received_in_window+=quantity;flow.delivery_ids.append(reference)
			flow.receipt_count+=1
			if not link.is_empty():link.received_in_window+=quantity;link.receipt_count+=1
			if order.get("accepted_day") is int and at>=int(order.accepted_day):
				var elapsed: int=at-int(order.accepted_day)
				flow.lead_quantity+=quantity;flow.lead_quantity_days+=quantity*elapsed
				flow.minimum_lead_days=elapsed if flow.minimum_lead_days==null else mini(elapsed,int(flow.minimum_lead_days))
				flow.maximum_lead_days=elapsed if flow.maximum_lead_days==null else maxi(elapsed,int(flow.maximum_lead_days))
			flow.last_delivery_day=at if flow.last_delivery_day==null else maxi(at,int(flow.last_delivery_day))
			if origin==destination:
				var local: Dictionary=_activity(nodes,origin,good)
				local.local_received+=quantity;local.delivery_ids.append(reference)
				continue
			for pair: Array in [[origin,destination,"sent"],[destination,origin,"received"]]:
				var activity: Dictionary=_activity(nodes,pair[0],good)
				activity[pair[2]]+=quantity;activity.delivery_ids.append(reference)
				if pair[1] not in activity.partners:activity.partners.append(pair[1])
	var received_by_need: Dictionary={}
	for link: Dictionary in links.values():
		var key: String=str(link.buyer_site)+"|"+str(link.good)
		received_by_need[key]=int(received_by_need.get(key,0))+int(link.received_in_window)
	for link: Dictionary in links.values():
		link["buyer_good_received_in_window"]=int(received_by_need[str(link.buyer_site)+"|"+str(link.good)])
		link["activity"]="RECENT_DELIVERY" if int(link.received_in_window)>0 else "NO_RECENT_TRADE" if link.last_delivery_day!=null else "NO_DELIVERY_YET"
		link["fulfilment"]="ACCEPTED_RESPONSIBILITY" if int(link.pending_responsibility)+int(link.transit_responsibility)>0 else "NO_OPEN_RESPONSIBILITY"
		link["availability"]="EXECUTION_AUTHORITY_NOT_QUERIED" if link.can_order_one==null else "CURRENTLY_EXECUTABLE_ONE" if link.can_order_one else "KNOWN_NOT_EXECUTABLE_NOW"
	return {"schema":"merchant_observed_contacts_v2","scope":"OWN_RECEIVED_OFFERS_AND_OWN_DELIVERY_RECEIPTS","minute":minute,"window_start_day":start,"window_end_day":day,"window_days":WINDOW_DAYS,"contacts":contacts,"nodes":nodes,"flows":flows,"links":links,"basis":"COMMODITY_SPECIFIC_OBSERVED_ACTIVITY_NOT_GLOBAL_MARKET_CENTRE","permanent_hinterland":false}
