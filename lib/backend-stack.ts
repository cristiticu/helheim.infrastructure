import { aws_dynamodb, CfnOutput, RemovalPolicy, Stack, StackProps } from 'aws-cdk-lib';
import { Construct } from 'constructs';

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
                    indexName: 'gsi.realm-lookup',
                    partitionKey: {
                        name: 'user_guid',
                        type: aws_dynamodb.AttributeType.STRING,
                    },
                    sortKey: {
                        name: 'realm_guid',
                        type: aws_dynamodb.AttributeType.STRING,
                    },

                    projectionType: aws_dynamodb.ProjectionType.INCLUDE,

                    nonKeyAttributes: ['role', 'joined_at'],
                },
            ],
        });

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
