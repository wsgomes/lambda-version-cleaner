import os
import re
import boto3
import threading

lambda_client = boto3.client('lambda', region_name=os.getenv('THIS_AWS_REGION', None))

keep = int(os.getenv('VERSIONS_TO_KEEP', '3'))
pattern = os.getenv('FUNCTION_NAME_PATTERN', '.*')  # Default to match all if not provided
function_names = os.getenv('FUNCTION_NAMES', '')  # Comma-separated list of function names

class ExceptionThread(threading.Thread):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._exception = None

    def run(self):
        try:
            if self._target:
                self._target(*self._args, **self._kwargs)
        except Exception as e:
            self._exception = e

    def join(self, *args, **kwargs):
        super().join(*args, **kwargs)
        return self._exception

def process_function_versions(function_name):
    response = lambda_client.list_versions_by_function(FunctionName=function_name)
    versions = [int(v['Version']) for v in response['Versions'] if v['Version'] != '$LATEST']
    if len(versions) <= keep:
        print(f"Function {function_name} has {len(versions)} versions, skipping")
        return
    
    versions.sort(reverse=True)
    versions_to_delete = versions[keep:]
    for version in versions_to_delete:
        lambda_client.delete_function(FunctionName=function_name, Qualifier=str(version))
        print(f"Deleted version {version} of function {function_name}")

def lambda_handler(event, context):
    exceptions = []
    try:
        if function_names:
            functions = function_names.split(',')
        else:
            response = lambda_client.list_functions()
            functions = [function['FunctionName'] for function in response['Functions']]
        
        threads = []
        for function_name in functions:
            if re.match(pattern, function_name):
                thread = ExceptionThread(target=process_function_versions, args=(function_name,))
                threads.append(thread)
                thread.start()
        
        for thread in threads:
            exception = thread.join()
            if exception:
                exceptions.append(str(exception))
    
    except Exception as e:
        exceptions.append(str(e))
    
    return {
        'statusCode': 200 if not exceptions else 500,
        'body': {
            'status': 'OK' if not exceptions else 'Errors occurred',
            'exceptions': exceptions
        }
    }
