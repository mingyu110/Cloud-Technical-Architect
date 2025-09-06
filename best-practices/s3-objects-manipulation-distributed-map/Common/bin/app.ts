#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { DistributedMapCommonStack } from '../lib/app-stack';

const app = new cdk.App();
new DistributedMapCommonStack(app, 'distributed-map-common-stack');