import { Construct } from 'constructs';
import { Bucket } from 'aws-cdk-lib/aws-s3';
import { RemovalPolicy, Stack, StackProps } from 'aws-cdk-lib';
import { Topic } from 'aws-cdk-lib/aws-sns';
import { StringParameter } from 'aws-cdk-lib/aws-ssm';

export class DistributedMapCommonStack extends Stack {
  constructor(scope: Construct, id: string, props?: StackProps) {
    super(scope, id, props);

    const topic = new Topic(this, 'Topic');
    const inputBucket = new Bucket(this, "InputBucket", {
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true
    });

    new StringParameter(this, 'ParameterTopicArn', {
      parameterName: '/distributed-map/commons/topic/arn',
      stringValue: topic.topicArn
    });

    new StringParameter(this, 'ParameterBucketArn', {
      parameterName: '/distributed-map/commons/bucket/arn',
      stringValue: inputBucket.bucketArn
    });
  }
}
