# Deploying and Operationalizing a Coworking Space Microservice Guide

## Preparation

### Workspace Environment Requirements

- **Python Environment**: run Python 3.10+ applications and install Python dependencies via pip
- **Kubectl CLI**: Manage K8s resources
- **Helm CLI**: Manage packages
- **Git:** Manage your version control source code
- **AWS CLI**: Configure the AWS account
- **Eksctl CLI**: Create/Delete the eks cluster

### AWS Environment Requirements

- **ECR**: Manage your Docker image after building by CodeBuild
- **EKS**: Manage your K8s Cluster
- **CodeBuild**: Build your Dockerfile then push to the ECR
- **IAM**: Manage EKS cluster role

## Create a new Admin User

Type IAM in the search bar then click IAM Select User

![image-20240305201601063](C:\Users\YetMaHaiBon\AppData\Roaming\Typora\typora-user-images\image-20240305201601063.png)

Then Select the Create User

![image-20240305201704419](C:\Users\YetMaHaiBon\AppData\Roaming\Typora\typora-user-images\image-20240305201704419.png)

Fill in your username then tick **Provide user access** below, Select **Custom password** and type your password, and then untick the **Users must create a new password** then click Next

![image-20240305201805784](C:\Users\YetMaHaiBon\AppData\Roaming\Typora\typora-user-images\image-20240305201805784.png)

In the Set permissions page select **Attach policies directly** and type **Administrator Access** in the search bar then tick it then click Next.

![image-20240305202052697](C:\Users\YetMaHaiBon\AppData\Roaming\Typora\typora-user-images\image-20240305202052697.png)

In the **Review and create** page scroll down and then click the **Create User** button if you don't change any information

![image-20240305202442253](C:\Users\YetMaHaiBon\AppData\Roaming\Typora\typora-user-images\image-20240305202442253.png)

Copy the Console sign-in URL and paste to your note in case login in the next time.

![image-20240305202614985](C:\Users\YetMaHaiBon\AppData\Roaming\Typora\typora-user-images\image-20240305202614985.png)

Next, we'll create Access Key to use to config the AWS CLI profile, we firslt login with the new created user then go to the IAM > User and then select the username you created, and then select the **Security credentials**, scroll down to the Access Key and then select **Create access key**

![image-20240305203514618](C:\Users\YetMaHaiBon\AppData\Roaming\Typora\typora-user-images\image-20240305203514618.png)

Select the Command Line Interface (CLI) and then tick the box **I understand** and click Next

![image-20240305203604337](C:\Users\YetMaHaiBon\AppData\Roaming\Typora\typora-user-images\image-20240305203604337.png)

Type your description tag if need or you can skip this page by clicking the **Create access key**

![image-20240305203737255](C:\Users\YetMaHaiBon\AppData\Roaming\Typora\typora-user-images\image-20240305203737255.png)

Finally, copy and store both the **Access key** and **Secret access key** or you can download the .csv file and store it in your computer. Then click **Done**

![image-20240305204053489](C:\Users\YetMaHaiBon\AppData\Roaming\Typora\typora-user-images\image-20240305204053489.png)

Configure the profile for the user by running this command:

`aws configure`

Then fill in the **Access key** and the **Secret access key**

After finishing configuring aws cli for the user. Next we'll process to deploy the EKS Cluster.

### Deploy the EKS Cluster

Before create the EKS Cluster, we need to make sure the AWS CLI configured correctly for the user

`aws sts get-caller-identity`

Next, run this command to create the cluster

`eksctl create cluster --name <yourclustername> --version 1.29 --region <currentregion> --nodegroup-name <nodegroupname> --node-type t3.medium --nodes 1 --nodes-min 1 --nodes-max 2`

After the cluster created, run following commands to approve the IAM OIDC Provider, create the IAM service account and addon for the cluster 

`eksctl utils associate-iam-oidc-provider --cluster=<yourclustername> --region <yourcurrentregion> --approve`

`eksctl create iamserviceaccount \
--region <yourcurrentreagion> \
--name ebs-csi-controller-sa \
--namespace kube-system \
--cluster <yourclustername> \
--attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
--approve \
--role-only \
--role-name AmazonEKS_EBS_CSI_DriverRole` 

`eksctl create addon --name aws-ebs-csi-driver --cluster <yourclustername> --service-account-role-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/AmazonEKS_EBS_CSI_DriverRole --force`

After these commands finishing. Next, we need to update the **Kubeconfig** to update the context in the local Kubernetes file in order to access the cluster

`aws eks --region <currentregion> update-kubeconfig --name <yourclustername>`

## Deploy PostgreSQL Dabatase Using Helm

### Configure the PostgreSQL Database for the Service

First off all, we need to create both pv and pvc for postgresql

**postgresql-pv.yaml**

```
apiVersion: v1
kind: PersistentVolume
metadata:
  name: postgresql-pv
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: gp2
  hostPath:
    path: "/mnt/data"
```

**postgresql-pvc.yaml**

```
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgresql-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

Run `kubectl apply -f` for each file. After that, we'll process to install PostgreSQL by using Helm

First, add **bitnami** repo with command 

`helm repo add bitnami https://charts.bitnami.com/bitnami`

Install the PostgreSQL by running command:

`helm install <your-release-name> bitnami/postgresql --set persistence.existingCl
aim=persistentvolumeclaim/<your-pv-claim> --set volumePermissions.enabled=true`

After finish the install command, let's get the password initiated

`export POSTGRES_PASSWORD=$(kubectl get secret --namespace default <Your-PostgreSQL-Service> -o jsonpath="{.data.postgres-password}" | base64 -d)`

Store your password in somewhere on your local machine

`echo $POSTGRES_PASSWORD > yourstorefile.txt`

Next, forward the postgresql service port for connecting to the database

`kubectl port-forward service/<your-postgresql-service> 5433:5432 &`

Now, go to the **db/** folder and process to import **.sql** files to the database

`PGPASSWORD="$POSTGRES_PASSWORD" psql --host 127.0.0.1 -U postgres -d postgres -p 5433 < <current_file.sql>`

## Building your Docker image

First, create the Dockerfile with following instructions

```
FROM python:3.10-slim-buster
USER root
WORKDIR /src
COPY ./analytics/requirements.txt requirements.txt
RUN pip install -r requirements.txt
COPY ./analytics .
CMD ["python", "app.py"]
```

Next, we'll create the ECR to store the Docker image, first go to the AWS and then type ECR in the search bar and click to it

Click **Get Started** button

![image-20240306124908238](C:\Users\YetMaHaiBon\AppData\Roaming\Typora\typora-user-images\image-20240306124908238.png)

Select **Private** option, and then type your repository name you want to create and then click **Create repository** in the end of the page

![image-20240306125032603](C:\Users\YetMaHaiBon\AppData\Roaming\Typora\typora-user-images\image-20240306125032603.png)

After create the ECR, select the ECR you created and then Select the **View push commands**, copy all the instruction and store it in your local computer. There're two tab Linux/MacOS and Windows, copy the right instruction following your OS Evironment that you're working in

![image-20240306135537822](C:\Users\YetMaHaiBon\AppData\Roaming\Typora\typora-user-images\image-20240306135537822.png)

Next, we have to create the **buildspec.yml** file to declare the build step for Codebuild. Here the example

```
version: 0.2

phases:
  pre_build:
    commands:
      - echo Logging into ECR before build
      - aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com
  build:
    commands:
      - echo Starting build at `date`
      - echo Building Docker Image waiting...          
      - docker build -t $IMAGE_NAME:$IMAGE_TAG .
      - docker tag $IMAGE_NAME:$IMAGE_TAG $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_NAME:$IMAGE_TAG
  post_build:
    commands:
      - echo Completed build at `date`
      - echo Pushing the Docker image to the ECR waiting...
      - docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_NAME:$IMAGE_TAG

```

Next, we will create the Codebuild Project to build your Docker image, type Codebuild in the search bar and click Codebuild, then we click the **Create project** button

![image-20240306125222710](C:\Users\YetMaHaiBon\AppData\Roaming\Typora\typora-user-images\image-20240306125222710.png)

Type your wish project name

![image-20240306125743730](C:\Users\YetMaHaiBon\AppData\Roaming\Typora\typora-user-images\image-20240306125743730.png)

In the **Source** section, we will use **GitHub** as source provider, and then select **Connect using Oauth** option

![image-20240306130101681](C:\Users\YetMaHaiBon\AppData\Roaming\Typora\typora-user-images\image-20240306130101681.png)

After connecting to the Github, select your current project to build the Docker Image

![image-20240306130218505](C:\Users\YetMaHaiBon\AppData\Roaming\Typora\typora-user-images\image-20240306130218505.png)



In the **Primary souce webhook events** we'll setup trigger build event every **PUSH** command to the Github, in the **Filter Group 1** click the topdown icon and then tick the PUSH option.

![image-20240306130248659](C:\Users\YetMaHaiBon\AppData\Roaming\Typora\typora-user-images\image-20240306130248659.png)

In the Environment leave the configuration as image below

![image-20240306130537958](C:\Users\YetMaHaiBon\AppData\Roaming\Typora\typora-user-images\image-20240306130537958.png)

In the **Service role** section, we'll new role name for this Project and the name of the role like codebuild-<Your>-<Project>-service-role. Remember to **tick the box** behind Priviledge

![image-20240306134634402](C:\Users\YetMaHaiBon\AppData\Roaming\Typora\typora-user-images\image-20240306134634402.png)

Leave it as default in **Certiicate** and **Compute**, in the Environment variable we'll create variables for running build buildspec.yml file. Here is the example for the variables

![image-20240306134944439](C:\Users\YetMaHaiBon\AppData\Roaming\Typora\typora-user-images\image-20240306134944439.png)

In the Buildspec section we select **Use a buildspecfile**

![image-20240306135143375](C:\Users\YetMaHaiBon\AppData\Roaming\Typora\typora-user-images\image-20240306135143375.png)

Leave the rest of configuration as default and then click the **Create build project** button 

![image-20240306135228428](C:\Users\YetMaHaiBon\AppData\Roaming\Typora\typora-user-images\image-20240306135228428.png)

After create Codebuild Project successfully, we need to config IAM Roles of the Codebuild service to give it full access to ECR. 

Go to the IAM tab, and then select Roles. Search the role name with format codebuild-<Your>-<Project>-service-role, then click to it. Next, scroll down to the **Permission policies**, click the **Add permissions**  and then choose **Create inline policy**

![image-20240306142231034](C:\Users\YetMaHaiBon\AppData\Roaming\Typora\typora-user-images\image-20240306142231034.png)

Select the JSON tab and then paste the below code to it, then scroll down to the end of the page click Next

```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ecr:*"
            ],
            "Resource": [
                "*"
            ]
        }
    ]
}
```

![image-20240306142407134](C:\Users\YetMaHaiBon\AppData\Roaming\Typora\typora-user-images\image-20240306142407134.png)

Fill in your Policy name you want and then click the **Create policy** button

![image-20240306142553896](C:\Users\YetMaHaiBon\AppData\Roaming\Typora\typora-user-images\image-20240306142553896.png)

Before deploy The coworking application, firstly we need to create both Configmap for storing DB information including username, port, database name, service name and Secret for storing db password

**postgresql-configmap.yaml**

```
apiVersion: v1
kind: ConfigMap
metadata:
  name: postgresql-config
  labels:
    app: postgres
data:
  DB_HOST: <Service Name Created by Helm>
  DB_PORT: <DB Port>
  DB_NAME: <Your DB Name>
  DB_USERNAME: <Your DB Username>
```

DB_Host value can get by using command **kubectl get svc**

**postgresql-secret.yaml**

```
apiVersion: v1
kind: Secret
metadata:
  name: postgresql-secret
type: Opaque
data:
  POSTGRES_PASSWORD: <Your Base64 Password>
```

POSTGRES_PASSWORD can be get by using command **echo "<Your Initiated Postgres Password>" | base64**

Running **kubectl apply -f** for each of file you've created

Edit the config.py

```
import logging
import os

from flask import Flask
from flask_sqlalchemy import SQLAlchemy

#db_username = os.environ["DB_USERNAME"]
#db_password = os.environ["DB_PASSWORD"]
db_username = os.environ.get("DB_USERNAME", "your db username")
db_password = os.environ.get("DB_PASSWORD", "your initiated postgres password")
# db_host = os.environ.get("DB_HOST", "127.0.0.1")
db_host = os.environ.get("DB_HOST", "postgres-service-created-by-helm")
db_port = os.environ.get("DB_PORT", "your db port")
db_name = os.environ.get("DB_NAME", "your db name")

app = Flask(__name__)
app.config["SQLALCHEMY_DATABASE_URI"] = f"postgresql://{db_username}:{db_password}@{db_host}:{db_port}/{db_name}"

db = SQLAlchemy(app)

app.logger.setLevel(logging.DEBUG)

```

Save the file and then commit and push to the Github

Next, we'll go to the AWS CodeBuild page to run the first build by clicking the button **Start Build** and then wait for the build success. After the build success you can see

![image-20240310212632516](C:\Users\YetMaHaiBon\AppData\Roaming\Typora\typora-user-images\image-20240310212632516.png)

Proceed to the ECR page to check if the image is pushed or not

![image-20240310212739150](C:\Users\YetMaHaiBon\AppData\Roaming\Typora\typora-user-images\image-20240310212739150.png) 

Click **Copy URI** icon and paste it to somewhere in your local machine, and then we'll create the Coworking Deployment yaml file to deploy the application

**coworking-deploy.yaml**

```
apiVersion: v1
kind: Service
metadata:
  name: coworking
spec:
  type: LoadBalancer
  selector:
    service: coworking
  ports:
  - name: "5153"
    protocol: TCP
    port: 5153
    targetPort: 5153
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: coworking
  labels:
    name: coworking
spec:
  replicas: 1
  selector:
    matchLabels:
      service: coworking
  template:
    metadata:
      labels:
        service: coworking
    spec:
      containers:
      - name: coworking
        image: <paste your ECR Image URI here>
        imagePullPolicy: IfNotPresent
        livenessProbe:
          httpGet:
            path: /health_check
            port: 5153
          initialDelaySeconds: 5
          timeoutSeconds: 2
        readinessProbe:
          httpGet:
            path: "/readiness_check"
            port: 5153
          initialDelaySeconds: 5
          timeoutSeconds: 5
        env:
        - name: DB_HOST
          valueFrom:
            configMapKeyRef:
              name: postgresql-config
              key: DB_HOST
        - name: DB_PORT
          valueFrom:
            configMapKeyRef:
              name: postgresql-config
              key: DB_PORT
        - name: DB_NAME
          valueFrom:
            configMapKeyRef:
              name: postgresql-config
              key: DB_NAME
        - name: DB_USERNAME
          valueFrom:
            configMapKeyRef:
              name: postgresql-config
              key: DB_USERNAME
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgresql-secret
              key: POSTGRES_PASSWORD
      restartPolicy: Always

```

Save it and then run the command **kubectl apply -f** to deploy the coworking application. Wait a moment till the application deployed. After that run **kubectl get pod** to check if the coworking pod running or not

![image-20240310213515118](C:\Users\YetMaHaiBon\AppData\Roaming\Typora\typora-user-images\image-20240310213515118.png)

Get the coworking service by running comand **kubectl get svc**

![image-20240310213651747](C:\Users\YetMaHaiBon\AppData\Roaming\Typora\typora-user-images\image-20240310213651747.png)

Copy the External-IP of coworking and then open the browser then paste it following the format

`<external-ip>:5153//api/reports/uer_visits`

![image-20240310213942829](C:\Users\YetMaHaiBon\AppData\Roaming\Typora\typora-user-images\image-20240310213942829.png)

## Configure log stream to Cloudwatch from Coworking Pod

You can prefer via [link](https://archive.eksworkshop.com/advanced/330_servicemesh_using_appmesh/add_nodegroup_fargate/cloudwatch_setup/), and remember to replace the current cluster name of the command with your cluster name before run it.

When you get into this step, run this following command to get this file into your local machine

curl -s https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/quickstart/cwagent-fluentd-quickstart.yaml

Open it and replace following these lines:

![image-20240310215747333](C:\Users\YetMaHaiBon\AppData\Roaming\Typora\typora-user-images\image-20240310215747333.png)

![image-20240310215854531](C:\Users\YetMaHaiBon\AppData\Roaming\Typora\typora-user-images\image-20240310215854531.png)

![image-20240310215925881](C:\Users\YetMaHaiBon\AppData\Roaming\Typora\typora-user-images\image-20240310215925881.png)

![image-20240310215959699](C:\Users\YetMaHaiBon\AppData\Roaming\Typora\typora-user-images\image-20240310215959699.png)

![image-20240310220017209](C:\Users\YetMaHaiBon\AppData\Roaming\Typora\typora-user-images\image-20240310220017209.png)

Save it and then run the command **kubectl apply -f** to deploy the agent

If you get this error while you deploying

> **AccessDeniedException**: User: arn:aws:sts::<AWS Account ID>:assumed-role/eksctl-<cluster-name>-nodegroup--NodeInstanceRole-<Random Code>/i-<Randomcode> is not authorized to perform: logs:PutLogEvents on resource: arn:aws:logs:us-east-1:<AWS Account ID>:log-group:/aws/containerinsights/<cluster-name>/performance:log-stream:ip-<Random IP Node>.ec2.internal because no identity-based policy allows the logs:PutLogEvents action

This is an AWS CloudWatch Logs access permission issue. 

To resolve this issue, you need to update the AWS Identity and Access Management (IAM) role policies associated with the assumed role `arn:aws:sts::<AWS Account ID>:assumed-role/eksctl-<cluster-name>-nodegroup--NodeInstanceRole-<Random Code>/i-<random code>` to grant the necessary permissions for CloudWatch Logs.

Here are the general steps to resolve the issue:

1. **Identify the IAM Role:** Identify the IAM role `eksctl-<cluster-name>-nodegroup--NodeInstanceRole-<random code>` associated with your EKS nodes.
2. **Update IAM Role Policies:** Update the IAM role policies associated with the identified role to include the necessary permissions for CloudWatch Logs.
   - Open the AWS Management Console.
   - Navigate to the IAM service.
   - In the left navigation pane, choose "Roles."
   - Search for and select the role named `eksctl-<cluster-name>-nodegroup--NodeInstanceRole-<random code>`.
   - Choose the "Permissions" tab.
   - Attach a policy that includes permissions for CloudWatch Logs. For example, you can attach the `CloudWatchLogsFullAccess` policy for testing purposes, and later refine the permissions based on your specific needs.





