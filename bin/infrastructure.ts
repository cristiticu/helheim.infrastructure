#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib/core';
import { ValheimServerStack } from '../lib/infrastructure-stack';

const app = new cdk.App();

const account = app.node.tryGetContext('account') || process.env.CDK_INTEG_ACCOUNT || process.env.CDK_DEFAULT_ACCOUNT;
new ValheimServerStack(app, 'Helheim-Infrastructure-Stack', {
    env: {
        account: account,
        region: 'eu-central-1',
    },
});
