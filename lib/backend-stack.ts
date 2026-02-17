import { aws_dynamodb, aws_iam, aws_lambda, CfnOutput, Duration, RemovalPolicy, Stack, StackProps } from 'aws-cdk-lib';
import { Platform } from 'aws-cdk-lib/aws-ecr-assets';
import { Construct } from 'constructs';
import path from 'path';

export class HelheimBackendStack extends Stack {
    constructor(scope: Construct, id: string, props?: StackProps) {
        super(scope, id, props);

        const authenticationTable = new aws_dynamodb.TableV2(this, `helheim.table.authentication`, {
            tableName: 'helheim.table.authentication',
            partitionKey: {
                name: 'guid',
                type: aws_dynamodb.AttributeType.STRING,
            },
            tableClass: aws_dynamodb.TableClass.STANDARD,
            billing: aws_dynamodb.Billing.onDemand(),
            removalPolicy: RemovalPolicy.RETAIN,
            globalSecondaryIndexes: [
                {
                    indexName: 'gsi.username',
                    partitionKey: {
                        name: 'username',
                        type: aws_dynamodb.AttributeType.STRING,
                    },
                    projectionType: aws_dynamodb.ProjectionType.ALL,
                    maxReadRequestUnits: 5,
                    maxWriteRequestUnits: 5,
                },
            ],
        });

        const realmsTable = new aws_dynamodb.TableV2(this, `helheim.table.realms`, {
            tableName: `helheim.table.realms`,
            partitionKey: {
                name: 'guid',
                type: aws_dynamodb.AttributeType.STRING,
            },
            sortKey: {
                name: 's_key',
                type: aws_dynamodb.AttributeType.STRING,
            },
            tableClass: aws_dynamodb.TableClass.STANDARD,
            billing: aws_dynamodb.Billing.onDemand(),
            removalPolicy: RemovalPolicy.RETAIN,
            globalSecondaryIndexes: [
                {
                    indexName: 'gsi.user-realms-lookup-2',
                    partitionKey: {
                        name: 'user_guid',
                        type: aws_dynamodb.AttributeType.STRING,
                    },
                    sortKey: {
                        name: 'guid',
                        type: aws_dynamodb.AttributeType.STRING,
                    },

                    projectionType: aws_dynamodb.ProjectionType.ALL,
                },
            ],
        });

        const helheimLambdaRole = new aws_iam.Role(this, 'HelheimLambdaRole', {
            roleName: `helheim.backend.lambda.role`,
            assumedBy: new aws_iam.ServicePrincipal('lambda.amazonaws.com'),
            managedPolicies: [aws_iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')],
        });

        helheimLambdaRole.addToPolicy(
            new aws_iam.PolicyStatement({
                actions: ['dynamodb:GetItem', 'dynamodb:PutItem', 'dynamodb:UpdateItem', 'dynamodb:DeleteItem', 'dynamodb:Query', 'dynamodb:Scan'],
                resources: [`arn:aws:dynamodb:${this.region}:${this.account}:table/helheim*`],
                effect: aws_iam.Effect.ALLOW,
            })
        );

        helheimLambdaRole.addToPolicy(
            new aws_iam.PolicyStatement({
                actions: ['ec2:TerminateInstances', 'ec2:CancelSpotInstanceRequests', 'ec2:DescribeInstances', 'ec2:DescribeSpotInstanceRequests'],

                resources: ['*'],
                effect: aws_iam.Effect.ALLOW,
            })
        );

        helheimLambdaRole.addToPolicy(
            new aws_iam.PolicyStatement({
                actions: ['s3:GetObject', 's3:PutObject', 's3:DeleteObject', 's3:ListBucket'],
                resources: [
                    `arn:aws:s3:::helheim*`, // For bucket-level actions (e.g., ListBucket)
                    `arn:aws:s3:::helheim*/*`, // For object-level actions (e.g., GetObject, PutObject)
                ],
                effect: aws_iam.Effect.ALLOW,
            })
        );

        helheimLambdaRole.addToPolicy(
            new aws_iam.PolicyStatement({
                actions: ['lambda:InvokeFunction'],
                resources: [
                    `arn:aws:lambda:${this.region}:${this.account}:function:helheim_instance_lambda`,
                    `arn:aws:lambda:${this.region}:${this.account}:function:helheim_vintage_story_instance_lambda`,
                ], // Use the specific ARN of the target Lambda
                effect: aws_iam.Effect.ALLOW,
            })
        );

        const dockerAssetDir = path.join(__dirname, '..', '..', 'backend');

        const helheimBackendLambda = new aws_lambda.DockerImageFunction(this, 'helheimBackendLambda', {
            functionName: 'helheim_backend_lambda_function',
            timeout: Duration.seconds(30),
            memorySize: 256,
            role: helheimLambdaRole,
            architecture: aws_lambda.Architecture.X86_64,
            code: aws_lambda.DockerImageCode.fromImageAsset(dockerAssetDir, {
                platform: Platform.LINUX_AMD64,
            }),

            environment: {
                CORS_ORIGINS: '["https://helheim.cristit.icu", "http://localhost:3000"]',
                ENVIRONMENT: 'production',
            },
        });

        const functionUrl = helheimBackendLambda.addFunctionUrl({
            authType: aws_lambda.FunctionUrlAuthType.NONE,
        });

        new CfnOutput(this, 'HelheimUrl', { value: functionUrl.url });

        new CfnOutput(this, 'ValheimUserAuthTableName', {
            value: authenticationTable.tableName,
            description: 'Name of the DynamoDB table for user authentication.',
        });

        new CfnOutput(this, 'ValheimServerDataTableName', {
            value: realmsTable.tableName,
            description: 'Name of the DynamoDB table for all server application data.',
        });
    }
}
