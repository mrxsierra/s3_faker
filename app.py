import json
import csv
import random
import re
import os
from collections import defaultdict
from faker import Faker
import pandas as pd
import fsspec  # for handling S3 paths

# ------------------------------
# Utility Functions
# ------------------------------

def load_valid_values(csv_path):
    """
    Loads a CSV file containing valid values.
    Returns a list of rows (each row is a list of cell values).
    Assumes the CSV file has a header row, which is skipped.
    """
    print(csv_path)
    if not os.path.exists(csv_path):
        raise FileNotFoundError(f"Valid values CSV file not found: {csv_path}")
    with open(csv_path, newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        # Skip header row
        next(reader, None)
        rows = list(reader)
    if not rows:
        raise ValueError(f"No data found in valid values CSV file: {csv_path}")
    return rows

def validate_value(value, pattern):
    """
    Validate the given value against a regex pattern.
    Returns True if it matches; otherwise, False.
    """
    if pattern is None:
        return True
    return re.fullmatch(pattern, str(value)) is not None

# ------------------------------
# Dependency Grouping
# ------------------------------

def build_dependency_groups(columns):
    """
    Build dependency groups for columns that reference each other via
    'same_valid_value_row_as_column'. Returns a mapping of column name to group id,
    and a dictionary mapping group id to a list of column names.
    
    NOTE: All columns in a dependency group must specify the same valid_values_csv.
    """
    # Build an undirected graph for linked columns.
    graph = defaultdict(set)
    for col in columns:
        col_name = col["name"]
        related = col.get("same_valid_value_row_as_column")
        if related:
            # Create bidirectional link between columns.
            graph[col_name].add(related)
            graph[related].add(col_name)
    
    # Find connected components in the graph.
    visited = set()
    groups = {}
    col_to_group = {}
    group_id = 0
    
    def dfs(node, current_group):
        visited.add(node)
        current_group.append(node)
        for neighbor in graph[node]:
            if neighbor not in visited:
                dfs(neighbor, current_group)
    
    for node in graph:
        if node not in visited:
            current_group = []
            dfs(node, current_group)
            for col_name in current_group:
                col_to_group[col_name] = group_id
            groups[group_id] = current_group
            group_id += 1

    return col_to_group, groups

# ------------------------------
# Data Generation Function
# ------------------------------

def generate_data(config):
    faker = Faker()
    num_rows = config.get("file_size", 1000)
    # Sort columns by their position in the output.
    columns = sorted(config.get("columns", []), key=lambda c: c["position"])
    
    # Preload any valid values CSV files.
    valid_csv_cache = {}
    for col in columns:
        csv_path = col.get("valid_values_csv")
        if csv_path and csv_path not in valid_csv_cache:
            valid_csv_cache[csv_path] = load_valid_values(csv_path)
    
    # Build dependency groups for columns that reference each other.
    col_to_group, groups = build_dependency_groups(columns)
    
    # Map column names to their configuration for quick lookup.
    col_config_by_name = {col["name"]: col for col in columns}
    
    generated_rows = []
    
    for _ in range(num_rows):
        row_data = {}
        processed_groups = set()  # Track dependency groups already processed for this row.
        
        # Process each column in the order defined by "position"
        for col in columns:
            col_name = col["name"]
            # If this column is part of a dependency group, process the entire group at once.
            if col_name in col_to_group:
                grp = col_to_group[col_name]
                if grp in processed_groups:
                    continue  # Already processed this group.
                group_cols = groups[grp]
                
                # Ensure that all columns in this group specify the same valid_values_csv.
                csv_files = {col_config_by_name[name]["valid_values_csv"] for name in group_cols}
                if len(csv_files) != 1:
                    raise ValueError(f"Columns in dependency group {group_cols} must use the same valid_values_csv.")
                valid_csv_file = csv_files.pop()
                valid_rows = valid_csv_cache[valid_csv_file]
                
                # Pick one random row from the CSV for the entire group.
                chosen_row = random.choice(valid_rows)
                for name in group_cols:
                    cfg = col_config_by_name[name]
                    col_index = cfg["valid_values_csv_column_index"]
                    value = chosen_row[col_index]
                    retries = 0
                    # Validate value if a regex is provided.
                    while not validate_value(value, cfg.get("validation_regex")) and retries < 10:
                        chosen_row = random.choice(valid_rows)
                        value = chosen_row[col_index]
                        retries += 1
                    if retries >= 10:
                        raise ValueError(f"Could not generate valid data for column {name} after 10 attempts.")
                    row_data[name] = value
                processed_groups.add(grp)
            else:
                # Process columns not in a dependency group.
                if col.get("valid_values_csv"):
                    valid_csv_file = col["valid_values_csv"]
                    valid_rows = valid_csv_cache[valid_csv_file]
                    chosen_row = random.choice(valid_rows)
                    col_index = col["valid_values_csv_column_index"]
                    value = chosen_row[col_index]
                    retries = 0
                    while not validate_value(value, col.get("validation_regex")) and retries < 10:
                        chosen_row = random.choice(valid_rows)
                        value = chosen_row[col_index]
                        retries += 1
                    if retries >= 10:
                        raise ValueError(f"Could not generate valid data for column {col_name} after 10 attempts.")
                    row_data[col_name] = value
                elif col.get("data_type"):
                    faker_method = getattr(faker, col["data_type"], None)
                    if not faker_method:
                        raise ValueError(f"Faker has no method for data_type '{col['data_type']}' in column '{col_name}'.")
                    value = faker_method()
                    retries = 0
                    while not validate_value(value, col.get("validation_regex")) and retries < 10:
                        value = faker_method()
                        retries += 1
                    if retries >= 10:
                        raise ValueError(f"Could not generate valid data for column {col_name} after 10 attempts.")
                    row_data[col_name] = value
                else:
                    # If neither valid_values_csv nor data_type is provided, assign None.
                    row_data[col_name] = None
        generated_rows.append(row_data)
    
    return generated_rows

# ------------------------------
# Writing Output Files
# ------------------------------

def write_outputs(data, output_files):
    """
    Write the generated data (a list of dictionaries) to the specified output files.
    Supports both local file system paths and S3 paths (paths starting with 's3://').
    """
    df = pd.DataFrame(data)
    
    for file_type, output_path in output_files.items():
        if output_path.startswith("s3://"):
            # Write to S3 using fsspec
            fs = fsspec.filesystem('s3')
            if file_type == "csv":
                with fs.open(output_path, 'w') as f:
                    df.to_csv(f, index=False)
            elif file_type == "json":
                with fs.open(output_path, 'w') as f:
                    f.write(df.to_json(orient="records", indent=2))
            elif file_type == "parquet":
                # to_parquet supports S3 paths when s3fs is installed.
                df.to_parquet(output_path, index=False)
            print(f"{file_type.upper()} file written to {output_path}")
        else:
            # Write to local file system.
            os.makedirs(os.path.dirname(output_path), exist_ok=True)
            if file_type == "csv":
                df.to_csv(output_path, index=False)
            elif file_type == "json":
                df.to_json(output_path, orient="records", indent=2)
            elif file_type == "parquet":
                df.to_parquet(output_path, index=False)
            print(f"{file_type.upper()} file written to {output_path}")

# ------------------------------
# Main Execution
# ------------------------------

def main():
    # Example JSON configuration. In practice, you might load this from a file.
    # "json": "s3://your-bucket/path/to/data.json"
    # "json": "output/data.json"
    config_json = """
    {
      "output_files": {
        "csv": "output/data.csv",
        "parquet": "output/data.parquet",
        "json": "s3://mamoke-bucket/json_data.json",
        "csv": "s3://mamoke-bucket/csv_data.csv",
        "parquet": "s3://mamoke-bucket/parquet_data.parquet"
      },
      "file_size": 1000,
      "columns": [
        {
          "index": 1,
          "name": "first_name",
          "position": 1,
          "data_type": "first_name",
          "valid_values_csv": null,
          "valid_values_csv_column_index": null,
          "same_valid_value_row_as_column": null,
          "validation_regex": null
        },
        {
          "index": 2,
          "name": "last_name",
          "position": 2,
          "data_type": "last_name",
          "valid_values_csv": null,
          "valid_values_csv_column_index": null,
          "same_valid_value_row_as_column": null,
          "validation_regex": null
        },
        {
          "index": 3,
          "name": "email",
          "position": 3,
          "data_type": "email",
          "valid_values_csv": null,
          "valid_values_csv_column_index": null,
          "same_valid_value_row_as_column": null,
          "validation_regex": "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\\\.[a-zA-Z]{2,}$"
        },
        {
          "index": 4,
          "name": "country",
          "position": 4,
          "data_type": null,
          "valid_values_csv": "valid_country_city.csv",
          "valid_values_csv_column_index": 0,
          "same_valid_value_row_as_column": "city",
          "validation_regex": null
        },
        {
          "index": 5,
          "name": "city",
          "position": 5,
          "data_type": null,
          "valid_values_csv": "valid_country_city.csv",
          "valid_values_csv_column_index": 1,
          "same_valid_value_row_as_column": "country",
          "validation_regex": null
        }
      ]
    }
    """
    config = json.loads(config_json)
    
    # Generate data rows.
    print("Generating data...")
    data = generate_data(config)
    
    # Write output files (local or S3, as specified in config["output_files"]).
    write_outputs(data, config.get("output_files", {}))
    print("Data generation completed.")

if __name__ == "__main__":
    main()

