// lambda/index.js
const { EC2Client, RunInstancesCommand, DescribeInstancesCommand, waitUntilInstanceRunning } = require('@aws-sdk/client-ec2');
const fs = require('fs');
const path = require('path');

const ec2Client = new EC2Client({});

const LAUNCH_TEMPLATE_ID = process.env.LAUNCH_TEMPLATE_ID;
const S3_BUCKET_NAME = process.env.S3_BUCKET_NAME;
const AWS_REGION = process.env.AWS_REGION;

const SCRIPT_FILENAME = 'startup.sh';

let USER_DATA_TEMPLATE;

try {
    USER_DATA_TEMPLATE = fs.readFileSync(path.join(__dirname, SCRIPT_FILENAME), 'utf8');
} catch (e) {
    // FATAL ERROR: If the core script is missing, the Lambda must fail immediately.
    console.error(`FATAL ERROR: Could not read template file ${SCRIPT_FILENAME}:`, e);
    throw new Error(`Initialization failed: Missing User Data script ${SCRIPT_FILENAME}`);
}

const sanitizeInput = (input) => {
    const safeInput = String(input || '');
    return safeInput.replace(/[;`$"<>]/g, '');
};

exports.handler = async (event) => {
    if (!event.realmGuid) {
        throw new Error('realmGuid is required in the event payload.');
    }

    const config = {
        serverName: sanitizeInput(event.serverName || "Helheim's Gate"),
        password: sanitizeInput(event.password || 'gymgym'),
        worldName: sanitizeInput(event.worldName || 'Dedicated'),
        realmGuid: sanitizeInput(event.realmGuid),
        preset: sanitizeInput(event.preset || ''),
        modifiers: event.modifiers || [],
        keys: event.keys || [],
        modpack: sanitizeInput(event.modpack || ''),
    };

    console.log('Configuration received:', { ...config, password: '***' });

    let presetFlag = '';
    let modifierFlags = '';
    let keyFlags = '';

    if (config.preset) {
        const presetValue = sanitizeInput(config.preset.toLowerCase());

        if (presetValue && presetValue !== 'normal') {
            presetFlag = `-preset ${presetValue}`;
        }
    }

    if (config.modifiers.length > 0) {
        for (const modifier of config.modifiers) {
            const modifierKey = sanitizeInput(modifier.key.toLowerCase());
            const modifierValue = sanitizeInput(modifier.value.toLowerCase());

            if (modifierKey && modifierValue && modifierValue !== 'normal') {
                modifierFlags = modifierFlags + ` -modifier ${modifierKey} ${modifierValue}`;
            }
        }
    }

    if (config.keys.length > 0) {
        for (const key of config.keys) {
            const keyValue = sanitizeInput(key.toLowerCase());

            if (keyValue) {
                keyFlags = keyFlags + ` -setkey ${keyValue}`;
            }
        }
    }

    let modpackS3 = '';

    if (config.modpack) {
        modpackS3 = `${S3_BUCKET_NAME}/${config.realmGuid}/modpack/${config.modpack}/`;
    }

    const finalUserDataScript = USER_DATA_TEMPLATE.replace(/#WORLD_S3/g, `${S3_BUCKET_NAME}/${config.realmGuid}/worlds/${config.worldName}/`)
        .replace(/#LISTS_S3/g, `${S3_BUCKET_NAME}/${config.realmGuid}/lists/`)
        .replace(/#USE_MODS/g, 'false')
        .replace(/#MODPACK_S3/g, modpackS3)
        .replace(/#REGION/g, AWS_REGION)
        .replace(/#SERVER_NAME/g, config.serverName)
        .replace(/#PASSWORD/g, config.password)
        .replace(/#WORLD/g, config.worldName)
        .replace(/#INSTANCE/g, '$(curl -s http://169.254.169.254/latest/meta-data/instance-id)')
        .replace(/#PRESET_FLAG/g, presetFlag)
        .replace(/#MODIFIER_FLAGS/g, modifierFlags)
        .replace(/#KEY_FLAGS/g, keyFlags);

    const base64UserData = Buffer.from(finalUserDataScript).toString('base64');

    const params = {
        MaxCount: 1,
        MinCount: 1,
        LaunchTemplate: {
            LaunchTemplateId: LAUNCH_TEMPLATE_ID,
        },
        UserData: base64UserData,
    };

    try {
        const runCommand = new RunInstancesCommand(params);
        const runData = await ec2Client.send(runCommand);
        const instanceId = runData.Instances[0].InstanceId;
        console.log('1. Successfully initiated instance launch:', instanceId);

        await waitUntilInstanceRunning(
            {
                client: ec2Client,
                maxWaitTime: 16,
                minDelay: 2,
            },
            {
                InstanceIds: [instanceId],
            }
        );
        console.log('2. Instance is now running. Fetching details...');

        const describeParams = {
            InstanceIds: [instanceId],
        };
        const describeCommand = new DescribeInstancesCommand(describeParams);
        const describeData = await ec2Client.send(describeCommand);

        const instanceDetails = describeData.Reservations[0].Instances[0];

        const publicIpAddress = instanceDetails.PublicIpAddress;
        const instanceType = instanceDetails.InstanceType;
        const launchTime = instanceDetails.LaunchTime.toISOString();
        const spotRequestId = instanceDetails.SpotInstanceRequestId;

        return {
            instanceId: instanceId,
            spotRequestId: spotRequestId,
            publicIpAddress: publicIpAddress,
            region: AWS_REGION,
            instanceType: instanceType,
            launchTime: launchTime,
            status: 'Server is running and ready for connection.',
            config: {
                serverName: config.serverName,
                worldName: config.worldName,
            },
        };
    } catch (error) {
        console.error('Error launching/describing EC2 instance:', error);
        throw new Error(`Failed to provision server: ${error.message || 'Unknown error'}`);
    }
};
