#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib/core';
import { ValheimServerStack } from '../lib/infrastructure/valheim-infrastructure-stack';
import { HelheimBackendStack } from '../lib/backend-stack';
import { HelheimFrontendStack } from '../lib/frontend-stack';
import { VintageStoryServerStack } from '../lib/infrastructure/vintage-story-infrastructure-stack';

const app = new cdk.App();
const account = app.node.tryGetContext('account') || process.env.CDK_INTEG_ACCOUNT || process.env.CDK_DEFAULT_ACCOUNT;

new ValheimServerStack(app, 'Helheim-Infrastructure-Stack', {
    env: {
        account: account,
        region: 'eu-central-1',
    },
});

new VintageStoryServerStack(app, 'VintageStory-Infrastructure-Stack', {
    env: {
        account: account,
        region: 'eu-central-1',
    },
});

new HelheimBackendStack(app, 'Helheim-Backend-Stack', {
    env: {
        account: account,
        region: 'eu-central-1',
    },
});

new HelheimFrontendStack(app, 'Helheim-Frontend-Stack', {
    env: {
        account: account,
        region: 'eu-central-1',
    },
    regionName: 'eu-central-1',
    frontendCertificate: '6767bca6-6e18-4adf-80ce-0212f75e2c6a',
});
