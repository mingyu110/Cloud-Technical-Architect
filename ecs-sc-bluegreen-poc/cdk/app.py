#!/usr/bin/env python3
import aws_cdk as cdk

from cdk.stack import CdkStack

app = cdk.App()
CdkStack(app, "EcsScBluegreenStack")

app.synth()
