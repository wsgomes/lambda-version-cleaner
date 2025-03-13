import os
import re
import boto3

from concurrent.futures import ThreadPoolExecutor, as_completed

lambda_client = boto3.client('lambda', region_name=os.getenv('THIS_AWS_REGION', None))

keep = int(os.getenv('VERSIONS_TO_KEEP', '3'))
pattern = os.getenv('FUNCTION_NAME_PATTERN', '.*')  # Default to match all if not provided
function_names = os.getenv('FUNCTION_NAMES', '')  # Comma-separated list of function names
thread_pool_size = int(os.getenv('THREAD_POOL_SIZE', '20'))  # Default thread pool size is 20

def list_all_versions(function_name):
    versions = []
    response = lambda_client.list_versions_by_function(FunctionName=function_name)
    versions.extend(response['Versions'])
    
    while 'NextMarker' in response:
        response = lambda_client.list_versions_by_function(FunctionName=function_name, Marker=response['NextMarker'])
        versions.extend(response['Versions'])
    
    return versions

def process_function_versions(function_name):
    versions = list_all_versions(function_name)
    versions = [int(v['Version']) for v in versions if v['Version'] != '$LATEST']
    if len(versions) <= keep:
        print(f"Function {function_name} has {len(versions)} versions, skipping")
        return
    
    versions.sort(reverse=True)
    versions_to_delete = versions[keep:]
    for version in versions_to_delete:
        lambda_client.delete_function(FunctionName=function_name, Qualifier=str(version))
        print(f"Deleted version {version} of function {function_name}")

def list_all_functions():
    functions = []
    response = lambda_client.list_functions()
    functions.extend(response['Functions'])
    
    while 'NextMarker' in response:
        response = lambda_client.list_functions(Marker=response['NextMarker'])
        functions.extend(response['Functions'])
    
    return [function['FunctionName'] for function in functions]

def lambda_handler(event, context):
    exceptions = []
    try:
        if function_names:
            functions = function_names.split(',')
        else:
            functions = list_all_functions()
        
        with ThreadPoolExecutor(max_workers=thread_pool_size) as executor:
            future_to_function = {executor.submit(process_function_versions, function_name): function_name for function_name in functions if re.match(pattern, function_name)}
            
            for future in as_completed(future_to_function):
                function_name = future_to_function[future]
                try:
                    future.result()
                except Exception as e:
                    exceptions.append(f"Function {function_name}: {str(e)}")
    
    except Exception as e:
        exceptions.append(str(e))
    
    return {
        'statusCode': 200 if not exceptions else 500,
        'body': {
            'status': 'OK' if not exceptions else 'Errors occurred',
            'exceptions': exceptions
        }
    }
