import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';

interface StackProps extends cdk.StackProps {
    regionName: string;
    frontendCertificate: string;
}

export class HelheimFrontendStack extends cdk.Stack {
    constructor(scope: Construct, id: string, props: StackProps) {
        super(scope, id, props);

        const bucketsCors = {
            allowedMethods: [cdk.aws_s3.HttpMethods.GET, cdk.aws_s3.HttpMethods.HEAD],
            allowedOrigins: ['*'],
            allowedHeaders: ['*'],
            maxAge: 60 * 30,
        };

        const frontendBucket = new cdk.aws_s3.Bucket(this, `helheim.frontend`, {
            bucketName: `helheim.frontend`,
            removalPolicy: cdk.RemovalPolicy.DESTROY,
            autoDeleteObjects: true,
            blockPublicAccess: cdk.aws_s3.BlockPublicAccess.BLOCK_ALL,
            accessControl: cdk.aws_s3.BucketAccessControl.BUCKET_OWNER_FULL_CONTROL,
            cors: [bucketsCors],
        });

        const frontendOac = new cdk.aws_cloudfront.S3OriginAccessControl(this, 'frontendOac', {
            originAccessControlName: `helheim.oac.frontend`,
        });

        const frontendCertificate = cdk.aws_certificatemanager.Certificate.fromCertificateArn(
            this,
            'HelheimFrontendCertificate',
            `arn:aws:acm:us-east-1:${this.account}:certificate/${props.frontendCertificate}`
        );

        const frontendCloudfront = new cdk.aws_cloudfront.Distribution(this, 'frontendCloudfront', {
            defaultBehavior: {
                origin: cdk.aws_cloudfront_origins.S3BucketOrigin.withOriginAccessControl(frontendBucket, {
                    originAccessControl: frontendOac,
                }),
                viewerProtocolPolicy: cdk.aws_cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
            },
            domainNames: ['helheim.cristit.icu'],
            certificate: frontendCertificate,
            priceClass: cdk.aws_cloudfront.PriceClass.PRICE_CLASS_100,
        });

        frontendBucket.addToResourcePolicy(
            new cdk.aws_iam.PolicyStatement({
                sid: 'AllowCloudFrontAccessOAC',
                effect: cdk.aws_iam.Effect.ALLOW,
                principals: [new cdk.aws_iam.ServicePrincipal('cloudfront.amazonaws.com')],
                actions: ['s3:GetObject'],
                resources: [`${frontendBucket.bucketArn}/*`],
                conditions: {
                    StringEquals: {
                        'AWS:SourceArn': `arn:aws:cloudfront::${this.account}:distribution/${frontendCloudfront.distributionId}`,
                    },
                },
            })
        );
    }
}
