# cdk/stack.py

from constructs import Construct
from aws_cdk import (
    Stack,
    aws_ec2 as ec2,
    aws_ecs as ecs,
    aws_iam as iam,
    aws_lambda as _lambda,
    aws_elasticloadbalancingv2 as elbv2,
    aws_codedeploy as codedeploy,
    Duration
)

class CdkStack(Stack):

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # --- 1. VPC and ECS Cluster ---
        vpc = ec2.Vpc(self, "BlueGreenVpc", max_azs=2)
        cluster = ecs.Cluster(self, "BlueGreenCluster", vpc=vpc)

        # --- 2. Application Load Balancer (ALB) ---
        alb = elbv2.ApplicationLoadBalancer(
            self, "BlueGreenAlb",
            vpc=vpc,
            internet_facing=True
        )
        listener = alb.add_listener("PublicListener", port=80, open=True)

        # --- 3. IAM Roles ---
        # Role for the ECS Tasks
        task_role = iam.Role(
            self, "EcsTaskRole",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com")
        )

        # Role for the Lambda validation function
        lambda_role = iam.Role(
            self, "LambdaHookRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ]
        )
        # Add policy to allow signaling back to CodeDeploy
        lambda_role.add_to_policy(iam.PolicyStatement(
            actions=["codedeploy:PutLifecycleEventHookExecutionStatus"],
            resources=["*"], # For a production stack, scope this down to the specific deployment group
        ))

        # --- 4. Lambda Validation Function ---
        validation_lambda = _lambda.Function(
            self, "ValidationLambda",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="validate.handler",
            code=_lambda.Code.from_asset("lambda"),
            role=lambda_role,
            timeout=Duration.seconds(30),
            environment={
                "ALB_URL": f"http://{alb.load_balancer_dns_name}"
            }
        )

        # --- 5. ECS Task Definitions (placeholders) ---
        # In a real project, you would define your containers here.
        # For this PoC, we assume task definitions are registered separately.
        frontend_task_definition = ecs.FargateTaskDefinition(self, "FrontendTaskDef", task_role=task_role)
        frontend_task_definition.add_container("nginx", image="public.ecr.aws/nginx/nginx:latest", port_mappings=[ecs.PortMapping(container_port=80)])

        backend_task_definition_v1 = ecs.FargateTaskDefinition(self, "BackendTaskDefV1", task_role=task_role)
        backend_task_definition_v1.add_container("backend-v1", image="public.ecr.aws/ecs-sample-applications/ecs-sample-app-color:blue", port_mappings=[ecs.PortMapping(container_port=80)])

        # --- 6. ECS Services with Service Connect and Blue/Green ---
        
        # Backend Service (the one we will update)
        backend_service = ecs.FargateService(self, "BackendService",
            cluster=cluster,
            task_definition=backend_task_definition_v1,
            service_connect_configuration=ecs.ServiceConnectConfiguration(
                namespace="my-app",
                services=[
                    ecs.ServiceConnectService(
                        port_mapping_name="backend-v1", # Must match a name in the task definition container
                        dns_name="backend",
                        port=8080
                    )
                ]
            ),
            # Blue/Green deployment configuration is added via CodeDeploy
        )

        # Frontend Service
        frontend_service = ecs.FargateService(self, "FrontendService",
            cluster=cluster,
            task_definition=frontend_task_definition,
            service_connect_configuration=ecs.ServiceConnectConfiguration(
                namespace="my-app"
            )
        )
        # Add frontend to ALB target group
        target_group = listener.add_targets("FrontendTarget",
            port=80,
            targets=[frontend_service],
            protocol=elbv2.ApplicationProtocol.HTTP
        )

        # --- 7. CodeDeploy Application and Deployment Group ---
        # This part connects the ECS service to CodeDeploy to enable blue/green
        codedeploy_app = codedeploy.EcsApplication(self, "CodeDeployApplication",
            application_name="ecs-bluegreen-codedeploy-app"
        )

        codedeploy.EcsDeploymentGroup(self, "BlueGreenDG",
            application=codedeploy_app,
            service=backend_service,
            blue_green_deployment_configuration=codedeploy.EcsBlueGreenDeploymentConfiguration(
                blue_target_group=target_group, # This is a simplification; a real setup needs separate target groups
                green_target_group=target_group, # managed by CodeDeploy.
                listener=listener,
                deployment_approval_wait_time=Duration.minutes(10),
                lifecycle_hooks=codedeploy.LifecycleHook(
                    function_name=validation_lambda.function_name,
                    lifecycle_stage="AfterAllowTestTraffic"
                ),
                terminate_blue_instances_on_deployment_success=True
            ),
            auto_rollback=codedeploy.AutoRollbackConfig(failed_deployment=True)
        )