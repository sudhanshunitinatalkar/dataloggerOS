import sqlite3
import json
import sys
import requests  # Requires: pip install requests
import paho.mqtt.client as mqtt  # Requires: pip install paho-mqtt
import time
import os  # <-- ADDED for path expansion
from datetime import datetime # <-- ADDED for test block
import database # <-- ADDED for test block (assumes database.py is in the same directory)

# --- NEW CONFIG FILE PATHS ---
# This file tells us WHERE the database is
MAIN_CONFIG_FILE = "testid-modbus.json"
# This file tells us WHERE to send the data (API/MQTT)
PUBLISH_CONFIG_FILE = "testid-publish.json"

def load_config(config_path):
    """
    Loads a single JSON configuration file.
    """
    print(f"Loading configuration from {config_path}...")
    try:
        with open(config_path, 'r') as f:
            config = json.load(f)
        return config
    except FileNotFoundError:
        print(f"FATAL ERROR: Configuration file '{config_path}' not found.", file=sys.stderr)
        return None
    except json.JSONDecodeError:
        print(f"FATAL ERROR: Could not decode JSON from '{config_path}'. Check format.", file=sys.stderr)
        return None
    except Exception as e:
        print(f"FATAL ERROR: An unexpected error occurred loading '{config_path}': {e}", file=sys.stderr)
        return None

def fetch_unpublished_data(db_path, limit=50):
    """
    Fetches a batch of unpublished records from the database.
    
    Returns:
        list: A list of tuples, where each tuple is (id, data_json_string).
    """
    records = []
    try:
        # NOTE: db_path is now the expanded, absolute path
        with sqlite3.connect(db_path) as conn:
            cursor = conn.cursor()
            # Select rows where is_published is 0
            cursor.execute(
                "SELECT id, data FROM readings WHERE is_published = 0 ORDER BY timestamp ASC LIMIT ?",
                (limit,)
            )
            records = cursor.fetchall()
    except sqlite3.Error as e:
        print(f"Error fetching unpublished data: {e}", file=sys.stderr)
        return []
        
    return records

def mark_data_as_published(db_path, record_ids):
    """
    Updates a list of record IDs to set is_published = 1.
    """
    if not record_ids:
        return True
        
    try:
        # NOTE: db_path is now the expanded, absolute path
        with sqlite3.connect(db_path) as conn:
            cursor = conn.cursor()
            # Create a string of placeholders (?,?,?)
            placeholders = ','.join(['?'] * len(record_ids))
            query = f"UPDATE readings SET is_published = 1 WHERE id IN ({placeholders})"
            
            cursor.execute(query, record_ids)
            conn.commit()
            print(f"Successfully marked {len(record_ids)} records as published.")
            return True
    except sqlite3.Error as e:
        print(f"Error marking data as published: {e}", file=sys.stderr)
        return False

def publish_to_api(api_config, data_payloads):
    """
    Publishes a batch of data to a single HTTP API endpoint.
    
    Args:
        api_config (dict): The configuration dictionary for one API.
        data_payloads (list): List of (id, json_string) tuples.
        
    Returns:
        bool: True on success, False on failure.
    """
    if not api_config.get('enabled', False):
        print("API endpoint is disabled. Skipping.")
        return True # Not a failure, just disabled

    url = api_config.get('url')
    api_key = api_config.get('api_key')
    timeout = api_config.get('timeout_seconds', 10)
    
    if not url or not api_key:
        print(f"Error: API config is missing 'url' or 'api_key'.", file=sys.stderr)
        return False

    headers = {
        'Content-Type': 'application/json',
        'X-API-Key': api_key  # Using X-API-Key, adjust if auth is Bearer token
    }
    
    # Convert list of JSON strings into a list of Python dicts
    # Then dump it back to a single JSON array string for batch upload
    try:
        json_objects = [json.loads(row[1]) for row in data_payloads]
        batch_payload = json.dumps(json_objects)
    except json.JSONDecodeError as e:
        print(f"Error serializing batch payload for API: {e}", file=sys.stderr)
        return False

    try:
        print(f"Sending batch of {len(data_payloads)} records to API: {url}...")
        response = requests.post(url, data=batch_payload, headers=headers, timeout=timeout)
        
        # Check for HTTP success codes (2xx)
        response.raise_for_status() 
        
        print(f"API Success (Status {response.status_code}).")
        return True
        
    except requests.exceptions.RequestException as e:
        print(f"Error publishing to API ({url}): {e}", file=sys.stderr)
        return False

def publish_to_mqtt(mqtt_config, data_payloads):
    """
    Publishes data to a single MQTT broker, one message per record.
    
    Args:
        mqtt_config (dict): The configuration dictionary for one broker.
        data_payloads (list): List of (id, json_string) tuples.
        
    Returns:
        bool: True on success, False on failure.
    """
    if not mqtt_config.get('enabled', False):
        print("MQTT broker is disabled. Skipping.")
        return True # Not a failure, just disabled

    host = mqtt_config.get('host')
    port = mqtt_config.get('port', 1883)
    topic_prefix = mqtt_config.get('topic_prefix')
    
    if not host or not topic_prefix:
        print(f"Error: MQTT config is missing 'host' or 'topic_prefix'.", file=sys.stderr)
        return False
    
    client = None
    try:
        client = mqtt.Client()
        if mqtt_config.get('username') and mqtt_config.get('password'):
            client.username_pw_set(mqtt_config['username'], mqtt_config['password'])
        
        print(f"Connecting to MQTT broker: {host}:{port}...")
        client.connect(host, port, 60)
        client.loop_start() # Start network loop

        # Define the full topic
        data_topic = f"{topic_prefix}/readings"
        
        print(f"Publishing {len(data_payloads)} messages to topic: {data_topic}...")
        
        for record_id, json_string in data_payloads:
            # Publish with QoS 1 (at least once)
            msg_info = client.publish(data_topic, payload=json_string, qos=1)
            
            # Wait for the message to be confirmed (robust publishing)
            msg_info.wait_for_publish(timeout=5) 
            if not msg_info.is_published():
                raise Exception(f"Message {record_id} failed to publish.")

        print("MQTT publish complete.")
        return True

    except Exception as e:
        print(f"Error publishing to MQTT ({host}): {e}", file=sys.stderr)
        return False
    finally:
        if client:
            client.loop_stop()
            client.disconnect()
            print("MQTT client disconnected.")


def main():
    """
    Main publishing loop.
    """
    print(f"--- Publisher script started at {time.asctime()} ---")
    
    # 1. Load BOTH config files
    main_config = load_config(MAIN_CONFIG_FILE)
    if main_config is None:
        sys.exit(1)
        
    publish_config = load_config(PUBLISH_CONFIG_FILE)
    if publish_config is None:
        sys.exit(1)
        
    # 2. Get database path from the MAIN config
    db_path = main_config.get("database", {}).get("db_path")
    if not db_path:
        print(f"FATAL ERROR: 'db_path' not found in '{MAIN_CONFIG_FILE}'", file=sys.stderr)
        sys.exit(1)
        
    # --- [FIX] Expand '~' to /home/user
    db_path = os.path.expanduser(db_path)

    # 3. Fetch data from DB
    unpublished_data = fetch_unpublished_data(db_path, limit=50)
    
    if not unpublished_data:
        print("No unpublished data found. Exiting.")
        return
        
    print(f"Found {len(unpublished_data)} unpublished records to process.")
    
    all_endpoints_succeeded = True
    record_ids = [row[0] for row in unpublished_data]
    
    # 4. Publish to all API endpoints (from PUBLISH config)
    for api_name, api_cfg in publish_config.get('api_endpoints', {}).items():
        print(f"\n--- Processing API: {api_name} ---")
        success = publish_to_api(api_cfg, unpublished_data)
        if not success:
            all_endpoints_succeeded = False
            print(f"Failed to publish to API: {api_name}.")
            # Stop trying other endpoints for this batch if one fails
            break 
            
    # 5. Publish to all MQTT brokers (from PUBLISH config)
    #    Only run this if all API endpoints were successful
    if all_endpoints_succeeded:
        for broker_name, mqtt_cfg in publish_config.get('mqtt_brokers', {}).items():
            print(f"\n--- Processing MQTT: {broker_name} ---")
            success = publish_to_mqtt(mqtt_cfg, unpublished_data)
            if not success:
                all_endpoints_succeeded = False
                print(f"Failed to publish to MQTT: {broker_name}.")
                # Stop trying other brokers for this batch if one fails
                break
                
    # 6. Mark as published ONLY if all enabled endpoints were successful
    if all_endpoints_succeeded:
        print("\nAll endpoints succeeded. Marking records as published.")
        mark_data_as_published(db_path, record_ids)
    else:
        print("\nOne or more endpoints failed. Records will NOT be marked as published and will be retried next time.")
        
    print(f"--- Publisher script finished at {time.asctime()} ---")


# --- [NEW] TEST BLOCK ---
if __name__ == "__main__":
    """
    This test block sets up a clean environment to test the publisher.
    It uses the 'database.py' file to create and populate a test database
    according to the config files, then runs the main() publisher logic
    and verifies that the data was marked as published.
    """
    
    print("--- [TEST BLOCK] ---")
    
    # 1. Load the main config to find the test.db path
    temp_config = load_config(MAIN_CONFIG_FILE)
    if temp_config is None:
        print("[TEST BLOCK] Failed to load main config. Exiting test.", file=sys.stderr)
        sys.exit(1)
        
    db_path = temp_config.get("database", {}).get("db_path")
    if not db_path:
        print(f"[TEST BLOCK] 'db_path' not found in '{MAIN_CONFIG_FILE}'", file=sys.stderr)
        sys.exit(1)
        
    # 2. IMPORTANT: Expand the path (e.g., '~' -> '/home/user')
    db_path = os.path.expanduser(db_path)
    
    print(f"[TEST BLOCK] Using database file: {db_path}")

    # 3. Clean up and initialize the database for a fresh test
    if os.path.exists(db_path):
        print(f"[TEST BLOCK] Removing old database: {db_path}")
        try:
            os.remove(db_path)
        except OSError as e:
            print(f"[TEST BLOCK] Error removing old database: {e}", file=sys.stderr)
            sys.exit(1)
    
    print("[TEST BLOCK] Initializing new database...")
    # Use the functions from 'database.py'
    database.initDB(db_path)

    # 4. Insert dummy data (that is UNPUBLISHED by default)
    print("[TEST BLOCK] Inserting 5 dummy rows...")
    for i in range(5):
        ts = datetime.now().isoformat()
        # Create a simple JSON string for the 'data' column
        dummy_json_data = json.dumps({"test_sensor": "value_abc", "reading": i})
        database.insertReading(db_path, ts, dummy_json_data)
        
    print("[TEST BLOCK] Dummy data inserted.")
    print("\n[TEST BLOCK] --- Running main() publish logic... ---")
    
    # 5. Run the main function
    main()
    
    print("[TEST BLOCK] --- Main() logic complete. ---")

    # 6. Verify the results
    print("[TEST BLOCK] Checking database to see if rows were marked as published...")
    try:
        with sqlite3.connect(db_path) as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT COUNT(*) FROM readings WHERE is_published = 0")
            unpublished_count = cursor.fetchone()[0]
            
            if unpublished_count == 0:
                print("[TEST BLOCK] \033[92mSUCCESS:\033[0m 0 unpublished rows found. Data was marked as published.")
            else:
                print(f"[TEST BLOCK] \033[91mFAILED:\033[0m {unpublished_count} unpublished rows remain. Publish must have failed.")
                print("[TEST BLOCK] (This is expected if API/MQTT endpoints are disabled or failed to connect)")
    except sqlite3.Error as e:
        print(f"[TEST BLOCK] Error checking final db state: {e}", file=sys.stderr)

    print("--- [TEST BLOCK] Finished. ---")