import { Construct } from 'constructs';
import { CustomState, DefinitionBody, Fail,  StateMachine, Succeed } from 'aws-cdk-lib/aws-stepfunctions';
import { Bucket } from 'aws-cdk-lib/aws-s3';
import { PolicyStatement } from 'aws-cdk-lib/aws-iam';
import { RemovalPolicy, Stack, StackProps } from 'aws-cdk-lib';
import { Topic } from 'aws-cdk-lib/aws-sns';
import { StringParameter } from 'aws-cdk-lib/aws-ssm';

export class DistributedMapStack extends Stack {
  constructor(scope: Construct, id: string, props?: StackProps) {
    super(scope, id, props);

    const { account: AWS_ACCOUNT_ID, region: AWS_REGION } = Stack.of(this);

    const commonTopic = Topic.fromTopicArn(this, 'CommonTopic', StringParameter.fromStringParameterName(this, 'ParameterTopicArn', '/distributed-map/commons/topic/arn' ).stringValue);
    const commonInputBucket = Bucket.fromBucketArn(this, "commonInputBucket", StringParameter.fromStringParameterName(this, 'ParameterInputBucketArn', '/distributed-map/commons/bucket/arn' ).stringValue);    

    const distributedMap = new CustomState(this, 'S3 Distributed Map State Machine', {
      stateJson: {
        MaxConcurrency: 10000,
        ToleratedFailurePercentage: 100,
        OutputPath: null,
        Type: "Map",
        Catch: [
          {
            ErrorEquals: [
              "States.ItemReaderFailed"
            ],
            Next: "Fail"
          }
        ],
        ItemBatcher: {
          MaxItemsPerBatch: 5000,
        },
        ItemProcessor: {
          ProcessorConfig: {
            ExecutionType: "STANDARD",
            Mode: "DISTRIBUTED"
          },
          StartAt: "ProcessObjects",
          States: {
            ProcessObjects: {
              MaxConcurrency: 1000,
              ToleratedFailurePercentage: 100,
              ItemsPath: "$.Items",
              ResultPath: null,
              OutputPath: null,
              End: true,
              Type: "Map",
              Catch: [
                {
                  ErrorEquals: [
                    "States.ItemReaderFailed"
                  ],
                  Next: "FailItem"
                }
              ],
              ItemBatcher: {
                MaxItemsPerBatch: 50,
              },
              ItemProcessor: {
                ProcessorConfig: {
                  ExecutionType: "STANDARD",
                  Mode: "DISTRIBUTED"
                },
                StartAt: "ProcessItems",
                States: {
                  ProcessItems: {
                    Type: "Map",
                    ResultPath: null,
                    OutputPath: null,
                    ItemsPath: "$.Items",
                    MaxConcurrency: 40,
                    ItemProcessor: {
                      ProcessorConfig: {
                        Mode: "INLINE"
                      },
                      StartAt: "GetObjectFromBucket",
                      States: {
                        GetObjectFromBucket: {
                          Type: "Task",
                          Next: "TransformItem",
                          Parameters: {
                            Bucket: commonInputBucket.bucketName,
                            "Key.$": "$.Key"
                          },
                          Resource: "arn:aws:states:::aws-sdk:s3:getObject"
                        },
                        TransformItem: {
                          Type: "Pass",
                          Next: "PublishItem",
                          Parameters: {
                            "output.$": "States.JsonMerge(States.StringToJson($.Body), States.StringToJson('{\"NewField\": \"MyValue\" }'), false)"
                          },
                          OutputPath: "$.output"
                        },
                        PublishItem: {
                          Type: "Task",
                          Resource: "arn:aws:states:::sns:publish",
                          Parameters: {
                            "Message.$": "$",
                            TopicArn: commonTopic.topicArn
                          },
                          End: true,
                          ResultPath: null
                        }
                      }
                    },
                    End: true
                  }
                }
              }
            },
            FailItem: {
              Type: "Fail"
            }
          }
        },
        ItemReader: {
          Parameters: {
            Bucket: commonInputBucket.bucketName
          },
          Resource: "arn:aws:states:::s3:listObjectsV2"
        }
      },
    })
    .addCatch(new Fail(this, 'Fail'))
    .next(new Succeed(this, 'Succeed'));
    
    const statemachineName = Stack.of(this).stackName + "MapStateMachine";

    const stateMachine = new StateMachine(this, 'StateMachine', {
      definitionBody: DefinitionBody.fromChainable(distributedMap),
      stateMachineName: statemachineName,
    });

    stateMachine.addToRolePolicy(
      new PolicyStatement({
        actions: ["states:StartExecution"],
        resources: [
          `arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${statemachineName}`,
        ],
      })
    );

    stateMachine.addToRolePolicy(
      new PolicyStatement({
        actions: [
          "s3:listObjectsV2",
          "s3:getObject"],
        resources: [`${commonInputBucket.bucketArn}/*`],
      })
    );

    stateMachine.addToRolePolicy(
      new PolicyStatement({
        actions: ["s3:ListBucket"],
        resources: [`${commonInputBucket.bucketArn}`],
      })
    );

    stateMachine.addToRolePolicy(
      new PolicyStatement({
        actions: ["sns:Publish"],
        resources: [commonTopic.topicArn],
      })
    );
  }
}
