import random
import json
import sys

def readsens(slave_id, function_code, mem_address, number_of_bytes, data_type, scaling_factor):
    
    dt_lower = data_type.lower()

    if 'int' in dt_lower:
        max_raw_value = (2 ** (number_of_bytes * 8)) - 1
        
        if max_raw_value <= 0:
            raw_value = 0
        else:
            raw_value = random.randint(0, max_raw_value)
        
        scaled_value = raw_value * scaling_factor
        return int(scaled_value)

    elif 'float' in dt_lower:
        max_raw_value = (2 ** (number_of_bytes * 8)) - 1

        if max_raw_value <= 0:
            raw_value = 0.0
        else:
            raw_value = random.randint(0, max_raw_value)
        
        scaled_value = raw_value * scaling_factor
        return scaled_value

    elif 'bool' in dt_lower:
        return random.choice([True, False])

    else:
        return None
    

def readsens_all(filename="cpuid.json"):
    """
    Reads sensor configuration from a JSON file, calls readsens for each,
    and prints the results as a dictionary.
    """
    try:
        with open(filename, 'r') as f:
            sensor_config = json.load(f)
    except FileNotFoundError:
        print(f"Error: Configuration file '{filename}' not found.", file=sys.stderr)
        return
    except json.JSONDecodeError:
        print(f"Error: Could not decode JSON from '{filename}'. Check file format.", file=sys.stderr)
        return
    except Exception as e:
        print(f"An error occurred opening or reading '{filename}': {e}", file=sys.stderr)
        return

    sensor_readings = {}
    
    if not isinstance(sensor_config, dict):
        print(f"Error: JSON content in '{filename}' is not a dictionary of sensors.", file=sys.stderr)
        return

    # Iterate through each sensor defined in the JSON
    for sensor_name, params in sensor_config.items():
        try:
            # Use keyword argument unpacking (**) to pass the dictionary
            # of parameters directly to the readsens function.
            value = readsens(**params)
            sensor_readings[sensor_name] = value
        except TypeError:
            # This will catch errors if 'params' is missing a required
            # argument for readsens (e.g., "slave_id" is missing)
            print(f"Error: Invalid or missing parameters for '{sensor_name}' in {filename}.", file=sys.stderr)
        except Exception as e:
            # Catch any other errors during the read
            print(f"Error reading sensor '{sensor_name}': {e}", file=sys.stderr)

    # Print the final dictionary of readings, as requested
    print(sensor_readings)

if __name__ == "__main__":
    readsens_all(filename="testid.json")
