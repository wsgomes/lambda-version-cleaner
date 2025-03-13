import boto3
import csv

from concurrent.futures import ThreadPoolExecutor, as_completed

lambda_client = boto3.client('lambda', region_name='us-west-2')

def count_versions(function_name):
    versions = []
    response = lambda_client.list_versions_by_function(FunctionName=function_name)
    versions.extend(response['Versions'])
    
    while 'NextMarker' in response:
        response = lambda_client.list_versions_by_function(FunctionName=function_name, Marker=response['NextMarker'])
        versions.extend(response['Versions'])
    
    version_count = len([v for v in versions if v['Version'] != '$LATEST'])
    return function_name, version_count

def list_all_functions():
    functions = []
    response = lambda_client.list_functions()
    functions.extend(response['Functions'])
    
    while 'NextMarker' in response:
        response = lambda_client.list_functions(Marker=response['NextMarker'])
        functions.extend(response['Functions'])
    
    return [function['FunctionName'] for function in functions]

def process_functions(function_names):
    total_versions = 0
    results = []
    failed_functions = []

    with ThreadPoolExecutor(max_workers=10) as executor:
        future_to_function = {executor.submit(count_versions, fn): fn for fn in function_names}
        
        for future in as_completed(future_to_function):
            function_name = future_to_function[future]
            try:
                fn, count = future.result()
                print(f"{fn}: {count}")
                results.append((fn, count))
                total_versions += count
            except Exception as e:
                print(f"Error processing function {function_name}: {e}")
                failed_functions.append(function_name)

    return results, total_versions, failed_functions

def main():
    function_names = list_all_functions()
    results, total_versions, failed_functions = process_functions(function_names)

    if failed_functions:
        print("Retrying failed functions...")
        retry_results, retry_total_versions, _ = process_functions(failed_functions)
        results.extend(retry_results)
        total_versions += retry_total_versions

    print(f"Total versions: {total_versions}")

    with open('lambda_versions.csv', 'w', newline='') as csvfile:
        csvwriter = csv.writer(csvfile)
        csvwriter.writerow(['FunctionName', 'VersionCount'])
        csvwriter.writerows(results)

if __name__ == "__main__":
    main()
