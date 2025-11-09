import * as cdk from 'aws-cdk-lib';
import { Stack, StackProps, CfnOutput, aws_lambda } from 'aws-cdk-lib';
import { Vpc, SecurityGroup, Port, InstanceType, CfnLaunchTemplate, UserData, CfnVolume } from 'aws-cdk-lib/aws-ec2';
import { Role, ServicePrincipal, PolicyStatement, Effect, CfnInstanceProfile } from 'aws-cdk-lib/aws-iam';
import { NodejsFunction } from 'aws-cdk-lib/aws-lambda-nodejs';
import { Bucket } from 'aws-cdk-lib/aws-s3';
import { Construct } from 'constructs';
import * as fs from 'fs';
import * as path from 'path';

export class ValheimServerStack extends Stack {
    constructor(scope: Construct, id: string, props?: StackProps) {
        super(scope, id, props);

        const helheimAmi = 'ami-06fe323eec046c1ef';
        const keyPairName = 'Valhalla-Keys';
        const instanceType = new InstanceType('t3.medium');

        const vpc = new Vpc(this, 'ValheimVPC', {
            maxAzs: 1,
            natGateways: 0,
        });

        const securityGroup = new SecurityGroup(this, 'Valheim-SG-Infra', {
            vpc,
            description: 'Allows Valheim traffic and SSH access',
            allowAllOutbound: true,
        });

        const valheimPorts = [2456, 2457, 2458];
        // Allow SSH (Restrict this in production)
        securityGroup.addIngressRule(cdk.aws_ec2.Peer.anyIpv4(), Port.tcp(22), 'Allow SSH');
        // Allow Valheim UDP/TCP traffic from anywhere
        valheimPorts.forEach((port) => {
            securityGroup.addIngressRule(cdk.aws_ec2.Peer.anyIpv4(), Port.udp(port), `Valheim UDP Port ${port}`);
            securityGroup.addIngressRule(cdk.aws_ec2.Peer.anyIpv4(), Port.tcp(port), `Valheim TCP Port ${port}`);
        });

        const worldBucket = new Bucket(this, 'ValheimWorldBucket', {
            removalPolicy: cdk.RemovalPolicy.RETAIN, // CRUCIAL: Retain the bucket
            autoDeleteObjects: false,
        });

        const instanceRole = new Role(this, 'ValheimInstanceRole', {
            assumedBy: new ServicePrincipal('ec2.amazonaws.com'),
        });

        worldBucket.grantReadWrite(instanceRole);

        instanceRole.addToPolicy(
            new PolicyStatement({
                effect: Effect.ALLOW,
                actions: ['ec2:TerminateInstances', 'ec2:AttachVolume', 'ec2:DetachVolume', 'ec2:DescribeVolumes'],
                resources: [`*`],
            })
        );

        let userDataScript = fs.readFileSync(path.join(__dirname, '/lambda/startup.sh'), 'utf8');

        const placeholderUserData = UserData.custom(userDataScript);

        const instanceProfile = new CfnInstanceProfile(this, 'ValheimInstanceProfile', {
            // You can optionally set a specific name, or let CloudFormation generate one.
            instanceProfileName: 'ValheimInstanceProfile',
            roles: [
                instanceRole.roleName, // Associate the Role by its name
            ],
        });

        const launchTemplate = new CfnLaunchTemplate(this, 'ValheimEphemeralTemplate', {
            launchTemplateName: 'ValheimSpotServerTemplate',
            launchTemplateData: {
                imageId: helheimAmi,
                instanceType: instanceType.toString(),
                keyName: keyPairName,
                instanceInitiatedShutdownBehavior: 'terminate',
                iamInstanceProfile: { name: instanceProfile.instanceProfileName },
                userData: cdk.Fn.base64(placeholderUserData.render()),
                instanceMarketOptions: {
                    marketType: 'spot',
                    spotOptions: {
                        instanceInterruptionBehavior: 'terminate',
                        spotInstanceType: 'one-time',
                    },
                },

                networkInterfaces: [
                    {
                        associatePublicIpAddress: true,
                        deviceIndex: 0,
                        subnetId: vpc.publicSubnets[0].subnetId,
                        groups: [securityGroup.securityGroupId],
                    },
                ],
            },
        });

        const startServerLambdaRole = new Role(this, 'StartServerLambdaRole', {
            assumedBy: new ServicePrincipal('lambda.amazonaws.com'),
            managedPolicies: [cdk.aws_iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')],
        });

        startServerLambdaRole.addToPolicy(
            new PolicyStatement({
                effect: Effect.ALLOW,
                actions: ['iam:PassRole'],
                // The resource MUST be the ARN of the IAM Role that the EC2 instance will assume.
                resources: [instanceRole.roleArn],
            })
        );

        startServerLambdaRole.addToPolicy(
            new PolicyStatement({
                effect: Effect.ALLOW,
                actions: ['ec2:RunInstances', 'ec2:DescribeInstances', 'ec2:DescribeLaunchTemplates'],
                resources: [
                    '*',
                    `arn:aws:ec2:${this.region}:${this.account}:launch-template/${launchTemplate.ref}`,
                    `arn:aws:ec2:${this.region}:${this.account}:instance/*`,
                    `arn:aws:ec2:${this.region}:${this.account}:subnet/${vpc.publicSubnets[0].subnetId}`,
                    `arn:aws:ec2:${this.region}:${this.account}:security-group/${securityGroup.securityGroupId}`,
                ],
            })
        );

        const lambdaDir = path.join(__dirname, 'lambda');

        const startServerLambda = new aws_lambda.Function(this, 'StartValheimServerLambda', {
            runtime: aws_lambda.Runtime.NODEJS_20_X,
            handler: 'index.handler', // Points to the index.js file's handler function
            code: aws_lambda.Code.fromAsset(lambdaDir), // CDK zips the content of this folder
            timeout: cdk.Duration.seconds(30),
            environment: {
                LAUNCH_TEMPLATE_ID: launchTemplate.ref,
                S3_BUCKET_NAME: worldBucket.bucketName,
            },
            role: startServerLambdaRole,
        });

        new CfnOutput(this, 'LaunchTemplateId', {
            value: launchTemplate.ref,
            description: 'The ID of the Launch Template used to start Valheim Spot instances.',
        });
        new CfnOutput(this, 'WorldS3BucketName', {
            value: worldBucket.bucketName,
            description: 'S3 Bucket for Valheim World Syncing.',
        });
        new CfnOutput(this, 'SecurityGroupId', {
            value: securityGroup.securityGroupId,
            description: 'The Security Group ID to use when launching instances.',
        });
    }
}
