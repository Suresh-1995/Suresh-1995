import { Construct } from 'constructs'
import { App, TerraformOutput, TerraformStack } from 'cdktf'
import { AwsProvider } from '@cdktf/provider-aws'
import { variables } from './variables'
import {
  InternetGateway,
  NatGateway,
  Route,
  RouteTable,
  RouteTableAssociation,
  SecurityGroup,
  Subnet,
  Vpc,
} from '@cdktf/provider-aws/lib/vpc'
import { Eip, Instance } from '@cdktf/provider-aws/lib/ec2'
import { AcmCertificate } from '@cdktf/provider-aws/lib/acm'
import { DbSubnetGroup, RdsCluster, RdsClusterInstance } from '@cdktf/provider-aws/lib/rds'
import {
  IamAccessKey,
  IamGroup,
  IamGroupMembership,
  IamPolicyAttachment,
  IamRole,
  IamUser,
  IamUserLoginProfile,
} from '@cdktf/provider-aws/lib/iam'
import * as dotenv from 'dotenv'
dotenv.config({ path: '.env' })

class prodinfra extends TerraformStack {
  constructor(scope: Construct, name: string) {
    super(scope, name)

    new AwsProvider(this, 'infra-provider', {
      region: process.env.PROD_AWS_DEFAULT_REGION || '',
      accessKey: process.env.PROD_AWS_ACCESS_KEY_ID || '',
      secretKey: process.env.PROD_AWS_SECRET_ACCESS_KEY || '',
    })
    // created a vpc with 2 public & private subnets
    const vpc = new Vpc(this, 'cdktf-vpc', {
      cidrBlock: variables.HEADERS.vpc_cidr,
      tags: { Name: variables.HEADERS.vpc_name },
    })
    const publicsubnet1 = new Subnet(this, 'pub-sub1', {
      cidrBlock: variables.HEADERS.pub_sub1_cidr,
      vpcId: vpc.id,
      availabilityZone: 'us-east-1a',
      tags: { Name: variables.HEADERS.pub_sub1_name },
    })
    const publicsubnet2 = new Subnet(this, 'pub-sub2', {
      cidrBlock: variables.HEADERS.pub_sub2_cidr,
      vpcId: vpc.id,
      availabilityZone: 'us-east-1b',
      tags: { Name: variables.HEADERS.pub_sub2_name },
    })
    const privatesubnet1 = new Subnet(this, 'pvt-sub1', {
      cidrBlock: variables.HEADERS.pvt_sub1_cidr,
      vpcId: vpc.id,
      availabilityZone: 'us-east-1c',
      tags: { Name: variables.HEADERS.pvt_sub1_name },
    })
    const privatesubnet2 = new Subnet(this, 'pvt-sub2', {
      cidrBlock: variables.HEADERS.pvt_sub2_cidr,
      vpcId: vpc.id,
      availabilityZone: 'us-east-1d',
      tags: { Name: variables.HEADERS.pvt_sub2_name },
    })
    const igw = new InternetGateway(this, 'cdktf-igw', {
      vpcId: vpc.id,
      tags: { Name: variables.HEADERS.igw_name },
    })
    const publicRT = new RouteTable(this, 'pub-rt', {
      vpcId: vpc.id,
      tags: { Name: variables.HEADERS.public_rt },
    })
    new Route(this, 'publicrouting', {
      gatewayId: igw.id,
      destinationCidrBlock: '0.0.0.0/0',
      routeTableId: publicRT.id,
    })
    new RouteTableAssociation(this, 'cdktf-pub1', {
      routeTableId: publicRT.id,
      subnetId: publicsubnet1.id,
    })
    new RouteTableAssociation(this, 'cdktf-pub2', {
      routeTableId: publicRT.id,
      subnetId: publicsubnet2.id,
    })
    const eip = new Eip(this, 'nt-eip', {
      vpc: true,
      tags: { Name: variables.HEADERS.eip_name },
    })
    const NAT = new NatGateway(this, 'cdktf-ngw', {
      allocationId: eip.id,
      subnetId: publicsubnet1.id,
      tags: { Name: variables.HEADERS.ngw_name },
    })
    const privateRT = new RouteTable(this, 'pvt-rt', {
      vpcId: vpc.id,
      tags: { Name: variables.HEADERS.pvt_rt },
    })
    new Route(this, 'privaterouting', {
      natGatewayId: NAT.id,
      destinationCidrBlock: '0.0.0.0/0',
      routeTableId: privateRT.id,
    })
    new RouteTableAssociation(this, 'cdktf-pvt1', {
      routeTableId: privateRT.id,
      subnetId: privatesubnet1.id,
    })
    new RouteTableAssociation(this, 'cdktf-pvt2', {
      routeTableId: privateRT.id,
      subnetId: privatesubnet2.id,
    })
    //created security group for jumphost
    const jumpsg = new SecurityGroup(this, 'jump-SG', {
      name: variables.HEADERS.jump_sg_name,
      vpcId: vpc.id,
      ingress: [
        {
          protocol: 'tcp',
          fromPort: 22,
          toPort: 22,
          cidrBlocks: ['175.101.3.226/32', '182.71.17.50/32', '103.248.208.34/32'],
        },
      ],
      egress: [{ protocol: '-1', fromPort: 0, toPort: 0, cidrBlocks: ['0.0.0.0/0'] }],
      tags: { Name: variables.HEADERS.jump_sg_name },
    })
    //created security group for application loadbalancer
    const albsg = new SecurityGroup(this, 'alb-SG', {
      name: variables.HEADERS.lb_sg_name,
      vpcId: vpc.id,
      ingress: [
        { protocol: 'tcp', fromPort: 80, toPort: 80, cidrBlocks: ['0.0.0.0/0'] },
        { protocol: 'tcp', fromPort: 443, toPort: 443, cidrBlocks: ['0.0.0.0/0'] },
      ],
      egress: [{ protocol: '-1', fromPort: 0, toPort: 0, cidrBlocks: ['0.0.0.0/0'] }],
      tags: { Name: variables.HEADERS.lb_sg_name },
    })
    // creating security group for runner
    const runner = new SecurityGroup(this, 'runner-SG', {
      name: variables.HEADERS.runner_sg_name,
      vpcId: vpc.id,
      ingress: [
        {
          protocol: 'tcp',
          fromPort: 22,
          toPort: 22,
          cidrBlocks: ['175.101.3.226/32', '182.71.17.50/32', '103.248.208.34/32'],
        },
      ],
      egress: [{ protocol: '-1', fromPort: 0, toPort: 0, cidrBlocks: ['0.0.0.0/0'] }],
      tags: { Name: variables.HEADERS.runner_sg_name },
    })
    // created security group for rds
    const rdssg = new SecurityGroup(this, 'rds-SG', {
      name: variables.HEADERS.rds_sg_name,
      vpcId: vpc.id,
      ingress: [
        {
          protocol: 'tcp',
          fromPort: 5432,
          toPort: 5432,
          cidrBlocks: ['175.101.3.226/32', '182.71.17.50/32', '103.248.208.34/32'],
          securityGroups: [albsg.id, jumpsg.id, runner.id],
        },
      ],
      egress: [{ protocol: '-1', fromPort: 0, toPort: 0, cidrBlocks: ['0.0.0.0/0'] }],
      tags: { Name: variables.HEADERS.rds_sg_name },
    })
    // creating new runner instance
    new Instance(this, 'runner', {
      keyName: variables.HEADERS.key_pair,
      vpcSecurityGroupIds: [runner.id],
      instanceType: 'm5.large',
      subnetId: publicsubnet1.id,
      associatePublicIpAddress: true,
      ami: variables.HEADERS.ami,
      rootBlockDevice: { deleteOnTermination: true, volumeSize: 50, volumeType: 'gp2' },
      dependsOn: [runner],
      tags: { Name: 'prod-runner' },
    })
    // creating new jumphost instance
    new Instance(this, 'jump-instance', {
      keyName: variables.HEADERS.key_pair,
      vpcSecurityGroupIds: [jumpsg.id],
      instanceType: 't2.micro',
      subnetId: publicsubnet1.id,
      associatePublicIpAddress: true,
      ami: variables.HEADERS.ami,
      rootBlockDevice: { deleteOnTermination: true, volumeSize: 10, volumeType: 'gp2' },
      dependsOn: [jumpsg],
      tags: { Name: 'prod-jumphost' },
    })
    // creating ACM
    new AcmCertificate(this, 'cert', {
      domainName: variables.HEADERS.domain_name,
      validationMethod: 'DNS',
    })
    // creating db subnet group and aurora-postgresql db cluster
    const dbsub = new DbSubnetGroup(this, 'auroradb-subnet', {
      subnetIds: [privatesubnet1.id, privatesubnet2.id, publicsubnet1.id, publicsubnet2.id],
      tags: { Name: variables.HEADERS.dbsubnetgp_name },
    })
    const cluster = new RdsCluster(this, 'aurora', {
      clusterIdentifier: variables.HEADERS.cluster_idententifier,
      engine: variables.HEADERS.rds_engine,
      engineVersion: variables.HEADERS.rds_engine_ver,
      skipFinalSnapshot: true,
      databaseName: variables.HEADERS.rds_dbname,
      masterUsername: process.env.PROD_DB_USERNAME,
      masterPassword: process.env.PROD_DB_PASSWORD,
      vpcSecurityGroupIds: [rdssg.id],
      dbSubnetGroupName: dbsub.name,
      storageEncrypted: true,
      backupRetentionPeriod: 7,
    })
    new RdsClusterInstance(this, 'aurorainstance', {
      clusterIdentifier: cluster.id,
      engine: variables.HEADERS.rds_engine,
      engineVersion: variables.HEADERS.rds_engine_ver,
      instanceClass: variables.HEADERS.db_instance_class,
      tags: { Name: variables.HEADERS.dbinstance_name },
      autoMinorVersionUpgrade: true,
      promotionTier: 1,
      publiclyAccessible: false,
      performanceInsightsEnabled: true,
    })
    // creating IAM role for task definition
    new IamRole(this, `new-execution-role`, {
      name: `new-task-execution-role`,
      inlinePolicy: [
        {
          name: 'new-task-execution',
          policy: JSON.stringify({
            Version: '2012-10-17',
            Statement: [
              {
                Effect: 'Allow',
                Action: [
                  'ecr:GetAuthorizationToken',
                  'ecr:BatchCheckLayerAvailability',
                  'ecr:GetDownloadUrlForLayer',
                  'ecr:BatchGetImage',
                  'logs:CreateLogStream',
                  'logs:PutLogEvents',
                ],
                Resource: '*',
              },
            ],
          }),
        },
      ],
      assumeRolePolicy: JSON.stringify({
        Version: '2012-10-17',
        Statement: [
          {
            Action: 'sts:AssumeRole',
            Effect: 'Allow',
            Principal: { Service: 'ecs-tasks.amazonaws.com' },
          },
        ],
      }),
    })
    const group = new IamGroup(this, 'devgroup', {
      name: 'Amplify-dev-group',
    })
    // creating IAM users for dev team and providing console access
    const siva = new IamUser(this, 'siva', {
      name: 'sivaprasad',
    })
    const harsha = new IamUser(this, 'harsha', {
      name: 'sriharsha',
    })
    const satya = new IamUser(this, 'satya', {
      name: 'satyaprasad',
    })
    const mateus = new IamUser(this, 'mateus', {
      name: 'mateus',
    })
    const osmar = new IamUser(this, 'osmar', {
      name: 'osmar',
    })
    new IamGroupMembership(this, 'group-members', {
      group: group.name,
      name: 'members',
      users: [siva.name, harsha.name, satya.name, mateus.name, osmar.name],
    })

    // attaching policy to dev-team group
    new IamPolicyAttachment(this, 'rds-read', {
      name: 'rds',
      groups: [group.name],
      policyArn: 'arn:aws:iam::aws:policy/AmazonRDSReadOnlyAccess',
    })
    new IamPolicyAttachment(this, 'cloudwatch', {
      name: 'cloudwatch',
      groups: [group.name],
      policyArn: 'arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess',
    })
    new IamPolicyAttachment(this, 's3readonly', {
      name: 's3',
      groups: [group.name],
      policyArn: 'arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess',
    })
    // providing console access for dev-team users
    const sivaprofile = new IamUserLoginProfile(this, 'sivaconsole', {
      user: siva.name,
      passwordLength: 16,
      passwordResetRequired: false,
      pgpKey: 'keybase:suresh1995',
    })
    const harshaprofile = new IamUserLoginProfile(this, 'harshaconsole', {
      user: harsha.name,
      passwordLength: 16,
      passwordResetRequired: false,
      pgpKey: 'keybase:suresh1995',
    })
    const satyaprofile = new IamUserLoginProfile(this, 'satyaconsole', {
      user: satya.name,
      passwordLength: 16,
      passwordResetRequired: false,
      pgpKey: 'keybase:suresh1995',
    })
    const mateusprofile = new IamUserLoginProfile(this, 'mateusconsole', {
      user: mateus.name,
      passwordLength: 16,
      passwordResetRequired: false,
      pgpKey: 'keybase:suresh1995',
    })
    const osmarprofile = new IamUserLoginProfile(this, 'osmarconsole', {
      user: osmar.name,
      passwordLength: 16,
      passwordResetRequired: false,
      pgpKey: 'keybase:suresh1995',
    })
    // creating s3 full access user for backend
    const s3access = new IamUser(this, 's3access', {
      name: 's3prodfullaccess',
    })
    new IamPolicyAttachment(this, 's3full', {
      name: 's3access',
      users: ['s3prodfullaccess'],
      policyArn: 'arn:aws:iam::aws:policy/AmazonS3FullAccess',
      dependsOn: [s3access],
    })
    const access = new IamAccessKey(this, 'access', {
      user: s3access.name,
      pgpKey: 'keybase:suresh1995',
    })
    //outputs
    const output = new TerraformOutput(this, 'cname', {
      value: 'test',
    })
    output.addOverride('value', '${aws_acm_certificate.cert.domain_validation_options}')
    new TerraformOutput(this, 'sivapassword', {
      value: sivaprofile.encryptedPassword,
    })
    new TerraformOutput(this, 'harshapassword', {
      value: harshaprofile.encryptedPassword,
    })
    new TerraformOutput(this, 'satyapassword', {
      value: satyaprofile.encryptedPassword,
    })
    new TerraformOutput(this, 'mateuspassword', {
      value: mateusprofile.encryptedPassword,
    })
    new TerraformOutput(this, 'osmarpassword', {
      value: osmarprofile.encryptedPassword,
    })
    new TerraformOutput(this, 's3secret', {
      value: access.encryptedSecret,
    })

  }
}

const app = new App()
new prodinfra(app, 'infra')
app.synth()

