import uuid
from faker import Faker
import random as rnd
import constants as cnst
from datetime import datetime
import boto3
import json
from datetime import timedelta
import random

BASE_FIELDS = ['user_id','session_id','event_type','timestamp','page']
sqs = boto3.client('sqs', region_name='eu-north-1')
queue_url = 'https://sqs.eu-north-1.amazonaws.com/897913033152/ecom-behavior-events'

faker = Faker()

EVENT_SCHEMAS = {
    'add_to_cart': ['product_id','product_name','category','price','quantity'],
    'search': ['search_query','results_count'],
    'abandon_checkout': ['cart_value','abandonment_stage','items_count'],
    'apply_coupon': ['coupon_code','discount_percentage','cart_value'],
    'apply_filters': ['filter_type', 'results_count'],
    'open_product': ['product_id', 'product_name', 'price', 'category', 'source'],   
    'choose_payment_method': ['payment_type', 'cart_value'],     
    'remove_from_cart': ['product_id','product_name','category','quantity'],
    'unlike_product':['product_id','product_name','category'],
    'like_product': ['product_id','product_name','category'],
    'purchase': ['cart_items', 'cart_total', 'payment_type'],
    'logout': [],
    'login' : [] 
}

def generate_base_event(event_type, user_id, session_id, current_time):
    return {
        'user_id': user_id,
        'session_id': session_id,
        'timestamp': current_time.isoformat(),
        'event_type': event_type,
        'page': cnst.EVENT_PAGES[event_type]
    }

def generate_session():
    current_time = datetime.now()
    journey = rnd.choice(cnst.JOURNEYS)
    print("journey: ", journey)

    # checking for search 
    product_for_step = {}
    for i, event in enumerate(journey):
        if event == 'open_product':
            product = rnd.choice(cnst.PRODUCTS)
            product_for_step[i] = product
            # look backwards for the nearest search
            for j in range(i-1, -1, -1):
                if journey[j] == 'search':
                    product_for_step[j] = product
                    break
                elif journey[j] == 'open_product':
                    break  # stop if we hit another open_product

    user_id = str(uuid.uuid4())
    session_id = str(uuid.uuid4())
    events = []
    current_product = None
    cart = []
    chosen_payment_type = None
    discount = 0
    
    for i, event_type in enumerate(journey):
        current_time += timedelta(seconds=random.randint(10, 120))
        event = generate_base_event(event_type, user_id, session_id, current_time)

        # --- session-aware events handled directly ---

        if event_type == 'open_product':
            current_product = product_for_step.get(i, rnd.choice(cnst.PRODUCTS))
            event['product_id'] = current_product['product_id']
            event['product_name'] = current_product['product_name']
            event['price'] = current_product['price']
            event['category'] = current_product['category']
            event['source'] = generate_field_value('source')
            events.append(event)
            continue

        if event_type == 'search':
            linked_product = product_for_step.get(i)
            event['search_query'] = rnd.choice([linked_product['product_name'], linked_product['category']]) if linked_product else faker.sentence()
            event['results_count'] = rnd.randrange(0, 500)
            events.append(event)
            continue

        if event_type == 'add_to_cart':
            if current_product is None:
                current_product = rnd.choice(cnst.PRODUCTS)
            quantity = rnd.randrange(1, 5)
            cart.append({**current_product, 'quantity': quantity})
            event['product_id'] = current_product['product_id']
            event['product_name'] = current_product['product_name']
            event['category'] = current_product['category']
            event['price'] = current_product['price']
            event['quantity'] = quantity
            events.append(event)
            continue

        if event_type == 'remove_from_cart':
            if cart:
                removed = rnd.choice(cart)
                cart.remove(removed)
                current_product = removed
            event['product_id'] = current_product['product_id']
            event['product_name'] = current_product['product_name']
            event['category'] = current_product['category']
            event['quantity'] = current_product.get('quantity', 1)
            events.append(event)
            continue

        if event_type == 'apply_coupon':
            discount = rnd.randrange(5, 50, 5)
            cart_total = sum(p['price'] * p['quantity'] for p in cart)
            event['coupon_code'] = rnd.choice(cnst.COUPON_CODES)
            event['discount_percentage'] = discount
            event['cart_value'] = round(cart_total, 2)
            events.append(event)
            continue

        if event_type == 'choose_payment_method':
            chosen_payment_type = rnd.choice(cnst.PAYMENT_TYPES)
            cart_total = sum(p['price'] * p['quantity'] for p in cart)
            event['payment_type'] = chosen_payment_type
            event['cart_value'] = round(cart_total * (1 - discount / 100), 2)
            events.append(event)
            continue

        if event_type == 'purchase':
            cart_total = sum(p['price'] * p['quantity'] for p in cart) if cart else (current_product['price'] if current_product else 0)
            event['cart_items'] = cart if cart else [current_product]
            event['cart_total'] = round(cart_total * (1 - discount / 100), 2)
            event['payment_type'] = chosen_payment_type or rnd.choice(cnst.PAYMENT_TYPES)
            events.append(event)
            continue

        if event_type == 'abandon_checkout':
            cart_total = sum(p['price'] * p['quantity'] for p in cart)
            event['cart_value'] = round(cart_total * (1 - discount / 100), 2)
            event['abandonment_stage'] = generate_field_value('abandonment_stage')
            event['items_count'] = len(cart)
            events.append(event)
            continue

        if event_type in ['like_product', 'unlike_product']:
            event['product_id'] = current_product['product_id']
            event['product_name'] = current_product['product_name']
            event['category'] = current_product['category']
            events.append(event)
            continue

        # --- simple stateless events ---
        extra_fields = EVENT_SCHEMAS[event_type]
        for field in extra_fields:
            event[field] = generate_field_value(field)
        
        events.append(event)
    
    return events


def generate_field_value(field):
    if field == 'payment_type':
        return rnd.choice(cnst.PAYMENT_TYPES)
    if field == 'abandonment_stage':
        return rnd.choice(cnst.ABANDONMENT_STAGES)
    if field == 'source':
        return rnd.choice(cnst.SOURCES)
    if field == 'filter_type':
        return rnd.choice(cnst.FILTER_TYPES)
    if field == 'coupon_code':
        return rnd.choice(cnst.COUPON_CODES)
    if field == 'quantity':
        return rnd.randrange(1, 5)
    if field == 'results_count':
        return rnd.randrange(0, 500)
    if field == 'items_count':
        return rnd.randrange(1, 15)
    if field == 'discount_percentage':
        return rnd.randrange(5, 50, 5)


def send_to_sqs(events):
    for event in events:
        response = sqs.send_message(
            QueueUrl=queue_url,
            MessageBody=json.dumps(event)
        )

        print(f"Message ID: {response.get('MessageId')}")

def simulate_sessions(n):
    for _ in range(n):
        session_events = generate_session()
        print(session_events)
        send_to_sqs(events=session_events)

simulate_sessions(800)