# lambda/validate.py

import os
import json
import requests
import boto3

# Initialize the CodeDeploy client
codedeploy_client = boto3.client('codedeploy')

def handler(event, context):
    """
    This Lambda function is triggered by an Amazon ECS blue/green deployment lifecycle hook.
    It validates the 'green' deployment by sending a test request and then signals
    success or failure back to AWS CodeDeploy.
    """
    print(f"Received event: {json.dumps(event)}")

    # --- Extract execution details from the CodeDeploy event --- 
    try:
        deployment_id = event['DeploymentId']
        lifecycle_event_hook_execution_id = event['LifecycleEventHookExecutionId']
    except KeyError as e:
        print(f"Error: Could not extract required IDs from event: {e}")
        raise

    # --- Configuration from Environment Variables ---
    try:
        alb_url = os.environ['ALB_URL']
    except KeyError:
        print("Error: ALB_URL environment variable must be set.")
        # Signal failure back to CodeDeploy
        signal_hook_status(deployment_id, lifecycle_event_hook_execution_id, "Failed")
        raise

    # --- Test Logic ---
    test_header_name = "x-amzn-ecs-bluegreen-test"
    test_header_value = "test"
    headers = {test_header_name: test_header_value}
    expected_content = "Green Version"
    hook_status = "Failed" # Default to failure

    print(f"Sending test request to {alb_url} with header '{test_header_name}: {test_header_value}'")

    try:
        # Send the test request
        response = requests.get(alb_url, headers=headers, timeout=5)
        print(f"Received response: Status={response.status_code}, Body='{response.text[:200]}...'")

        # Validate the response
        if response.status_code == 200 and expected_content in response.text:
            print("Validation SUCCEEDED.")
            hook_status = "Succeeded"
        else:
            print(f"Validation FAILED. Status code: {response.status_code}, Expected content: '{expected_content}'")

    except requests.exceptions.RequestException as e:
        print(f"Validation FAILED due to a request exception: {e}")

    # --- Signal the result back to CodeDeploy --- 
    print(f"Signaling hook status '{hook_status}' back to CodeDeploy.")
    signal_hook_status(deployment_id, lifecycle_event_hook_execution_id, hook_status)

    return {
        'statusCode': 200,
        'body': json.dumps(f'Lifecycle hook execution finished with status: {hook_status}')
    }

def signal_hook_status(deployment_id, execution_id, status):
    """
    Uses the boto3 client to send the execution status of the lifecycle hook
    back to AWS CodeDeploy.
    """
    try:
        codedeploy_client.put_lifecycle_event_hook_execution_status(
            deploymentId=deployment_id,
            lifecycleEventHookExecutionId=execution_id,
            status=status
        )
    except Exception as e:
        # If signaling fails, log the error but don't crash the Lambda,
        # as the core validation logic has already run.
        print(f"Error signaling status to CodeDeploy: {e}")