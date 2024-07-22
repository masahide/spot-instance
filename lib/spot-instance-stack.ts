import * as cdk from "aws-cdk-lib";
import { Construct } from "constructs";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as iam from "aws-cdk-lib/aws-iam";
import * as autoscaling from "aws-cdk-lib/aws-autoscaling";
import * as fs from "fs";
import * as path from "path";

export class SpotInstanceStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const RECORD_NAME = "p.suzu.me.uk";
    const ZONE_ID = "Z08397422LH3IDIZRIAIU";
    const TTL = "300";
    const KEYPAIR = "masahide ed25519";
    const SPOTPRICE = "0.004";
    const ASG_NAME = "spotInstance01";
    const INTERVAL = "900";
    const discordWebhookUrl = process.env.DISCORD_WEBHOOK || "";

    const vpc = new ec2.Vpc(this, "VPC", {
      maxAzs: 3,
      natGateways: 0,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: "PublicSubnet",
          subnetType: ec2.SubnetType.PUBLIC,
        },
      ],
    });

    const securityGroup = new ec2.SecurityGroup(this, "SecurityGroup", {
      vpc,
      allowAllOutbound: true,
    });

    securityGroup.addIngressRule(ec2.Peer.anyIpv4(), ec2.Port.tcp(22), "Allow SSH");

    const role = new iam.Role(this, "InstanceRole", {
      assumedBy: new iam.ServicePrincipal("ec2.amazonaws.com"),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName("service-role/AmazonEC2SpotFleetTaggingRole"),
        iam.ManagedPolicy.fromAwsManagedPolicyName("AmazonRoute53FullAccess"),
      ],
    });
    role.addToPolicy(
      new iam.PolicyStatement({
        actions: ["autoscaling:SetDesiredCapacity"],
        resources: ["*"],
      })
    );

    const userDataScript = fs.readFileSync(path.join(__dirname, "../user-data.sh"), "utf8");
    let updatedUserDataScript = userDataScript
      .replace("YOUR_DISCORD_WEBHOOK_URL", discordWebhookUrl)
      .replace("$ASG_NAME", ASG_NAME)
      .replace("$ZONE_ID", ZONE_ID)
      .replace("$RECORD_NAME", RECORD_NAME)
      .replace("$INTERVAL", INTERVAL)
      .replace("$TTL", TTL);
    const userData = ec2.UserData.forLinux();
    userData.addCommands(updatedUserDataScript);

    const spotFleet = new autoscaling.AutoScalingGroup(this, "SpotFleet", {
      vpc,
      autoScalingGroupName: ASG_NAME,
      maxCapacity: 1,
      minCapacity: 0,
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T4G, ec2.InstanceSize.NANO),
      machineImage: new ec2.AmazonLinuxImage({
        generation: ec2.AmazonLinuxGeneration.AMAZON_LINUX_2023,
        cpuType: ec2.AmazonLinuxCpuType.ARM_64,
      }),
      securityGroup,
      role,
      // desiredCapacity: 0,
      spotPrice: SPOTPRICE,
      userData,
      keyPair: ec2.KeyPair.fromKeyPairName(this, "KeyPair", KEYPAIR),
    });

    new cdk.CfnOutput(this, "AutoScalingGroupName", {
      value: spotFleet.autoScalingGroupName,
    });
  }
}
