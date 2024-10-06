# README

This is a demo about deploying AWS solution to control [automatic starting and stopping AWS instances](https://docs.aws.amazon.com/solutions/latest/instance-scheduler-on-aws/solution-overview.html) using IaC, namely AWS CloudFormation and [sceptre](https://github.com/Sceptre/sceptre). This demo currently uses version `v3.0.5` of the [AWS solution release](https://github.com/aws-solutions/instance-scheduler-on-aws/releases).

## TL;DR

To deploy the solution to your AWS account simulating the instructions from the [AWS documentation](https://docs.aws.amazon.com/solutions/latest/instance-scheduler-on-aws/step-1-launch-the-instance-scheduler-hub-stack.html), run these steps:

1. Authenticate to your AWS account in CLI environment. Setup your AWS profile using the environment variables for AWS authentication (either `AWS_PROFILE` or `AWS_ACCESS_KEY_ID`+`AWS_SECRET_ACCESS_KEY`+`AWS_SESSION_TOKEN`) and `AWS_DEFAULT_REGION`. E.g. if your AWS profile is named as `my_aws_account` and you work on `ap-southeast-2` AWS region, run:

    ```shell
    AWS_PROFILE=my_aws_account
    AWS_DEFAULT_REGION=ap-southeast-2
    AWS_DEFAULT_REGION=ap-southeast-2
    export AWS_PROFILE 
    ```

2. Double check your authentication setup by running:

    ```shell
    aws sts get-caller-identity
    ```

    It should show the `UserId`, `Account`, and `Arn`.

3. Create and activate python virtual environment (optional, but very recommended):

    ```shell
    virtualenv .venv
    source .venv/bin/activate
    ```

4. Install the python modules from the list in [requirements.txt](./requirements.txt):

    ```shell
    pip install -r requirements.txt
    ```

5. Configure [sceptre/config/config.yaml](./sceptre/config/config.yaml). Use config.yaml.example in the same directory as the base, and edit the content to match your environment. At the very minimum you need to set `account_id_hub` to the AWS account ID where you deploy the solution. You can find it from the output of running `aws sts get-caller-identity` above.

<a id="deploy_the_solution"></a>
6. Deploy the solution:

    ```shell
    # Change to sceptre/ directory
    cd sceptre/
    # Deploy the solution
    # ensure you already set the value for AWS_DEFAULT_REGION environment variable
    sceptre --var aws_region=${AWS_DEFAULT_REGION} launch hub/solution.yaml
    ```

7. Ensure the stack is deployed successfully. Check AWS CloudFormation console, the stack name should be `instance-scheduler-hub-solution` and the status should be `CREATE_COMPLETE` for the first time.

## Requirements

- Linux environment.
- jq.
- Recent version of [python](https://www.python.org/).
- [sceptre](https://github.com/Sceptre/sceptre).
- AWS account with proper access (administrator level, or if you know how IAM works you can create your own policies to craft least privilege for this procedure).

## Using the instance-scheduler solution

Check the CloudFormation stack with the name `instance-scheduler-hub-solution`, look for the parameter with the key `TagName`. The value (if you don't change the `solution_namespace` value in [config.yaml](./sceptre/config/config.yaml)) should be `demo:scheduler-config`. You need to use this a tag key for your EC2 instance(s).
For the tag value, there are predefined schedules that you can immediately use with the following names:

  - uk-office-hours
  - stopped
  - seattle-office-hours
  - scale-up-down
  - running

In order to use the solution, you need to apply a tag on your EC2 instance(s) with they key `demo:scheduler-config` (or whatever value of `TagName` from the deployed solution) and the tag value one of the schedule names from above.

## Adding more schedules

See the [Operator Guide](https://docs.aws.amazon.com/solutions/latest/instance-scheduler-on-aws/operator-guide.html) for documentation reference. See [Manage schedules using Infrastructure as Code (IaC)](https://docs.aws.amazon.com/solutions/latest/instance-scheduler-on-aws/manage-schedules-using-infrastructure-as-code-iac.html) for the suggested IaC implementation. This repo offers configuring the schedule using IaC as per suggestion, but the CloudFormation [template](./sceptre/templates/schedules.yaml.j2) has been rewritten in Jinja format, and a configuration sample has been provided in [schedules.yaml](./sceptre/config/hub/schedules.yaml). In that sample, two additional schedules with the name `BrisbaneBusinessHours` and `SydneyStopAt5PM` will be created when you deploy the stack like this:

    ```shell
    # Change to sceptre/ directory
    cd sceptre/
    # Deploy the solution
    # ensure you already set the value for AWS_DEFAULT_REGION environment variable
    sceptre --var aws_region=${AWS_DEFAULT_REGION} launch hub/schedules.yaml
    ```

You can then use those schedules on your EC2 instances tag.

## Hub and Spoke for Secondary Accounts

To utilise the solution in [secondary accounts](https://docs.aws.amazon.com/solutions/latest/instance-scheduler-on-aws/step-2-optional-launch-the-remote-stack-in-secondary-accounts.html), you can deploy the stack under remote to deploy it your secondary account(s). Follow these steps:

1. Ensure you have updated the [top level config.yaml](./sceptre/config/config.yaml) (use the provided config.yaml.example for reference) and add the secondary account IDs to the file with proper variable names (e.g. one that represent the account name).

2. Edit the file [hub/solutions.yaml](./sceptre/config/hub/solution.yaml), and update this:

    ```yaml
        Principals: >
            {{account_id_remote1}}
    ```

    to include all the secondary accounts, for example:

    ```yaml
        Principals: >
            {{account_id_remote1}},
            {{account_id_remote2}},
            {{account_id_remote3}},
            {{account_id_remote4}}
    ```

    Please ensure the variable names match with the one you define in the [top level config.yaml](./sceptre/config/config.yaml).

3. Redeploy [the solution](#deploy_the_solution) to the hub account (where you deployed the instance-scheduler).

4. Deploy the remote solution to the secondary accounts:

    1. Authenticate to the secondary accounts and set the necessary AWS environment variables for authentication.
    2. Deploy the remote solution:

        ```shell
        # Change to sceptre/ directory
        cd sceptre/
        # Deploy the solution
        # ensure you already set the value for AWS_DEFAULT_REGION environment variable
        sceptre --var aws_region=${AWS_DEFAULT_REGION} launch remote
        ```

## Quickly Deploy to Multiple Secondary Accounts

If you:

  - have many AWS accounts to deploy to.
  - use a pattern where you can assume an administrator IAM role to those accounts from a single hub account, e.g. management account (not necessarily the same as the hub account for this instance-scheduler).

Then you can use the provided [deploy-cfn.sh](./deploy-cfn.sh) to quickly deploy the hub and spoke solution. The advantage of this is you don't need to manually authenticate to multiple accounts in CLI, but instead only once to the management account. You also don't need to copy the [remote/](./sceptre/config/remote/config.yaml) directory to multiple directory to represent different accounts and adding [sceptre_role](https://docs.sceptre-project.org/latest/docs/stack_config.html#sceptre-role) directives all the time.

Follow these steps:

1. Create accounts.json file in the top directory of this repo, use existing [accounts.json.example](./accounts.json.example) for reference. Put the account name and account ID pair into that accounts.json file.

2. Edit [deploy-cfn.sh](./deploy-cfn.sh), update the following line:

    ```shell
    AWS_ROLE_TO_ASSUME=FAODeployerRole
    ```

    Replace `FAODeployerRole` with the IAM role name in the hub account/secondary accounts that you will assume from the management account.

3. Authenticate to the AWS management account in CLI. Set your environment variables to authenticate to the management account (either `AWS_PROFILE` or `AWS_ACCESS_KEY_ID`+`AWS_SECRET_ACCESS_KEY`+`AWS_SESSION_TOKEN`) and `AWS_DEFAULT_REGION` pointing to your AWS region.

4. Deploy the hub solution like this, assuming you name your hub account in accounts.json as `hub`:

    ```shell
    ./deploy-cfn.sh \
    --account hub \
    --extra-vars aws_region=${AWS_DEFAULT_REGION} \
    --action deploy \
    --dry-run false \
    --item hub
    ```

    That command will deploy all the stacks under [hub](./sceptre/config/hub/) directory.

5. Deploy the remote (secondary accounts) like this to each secondary account, assuming you name your hub account in accounts.json as `remote1`:

    ```shell
    ./deploy-cfn.sh \
    --account remote1 \
    --extra-vars aws_region=${AWS_DEFAULT_REGION} \
    --action deploy \
    --dry-run false \
    --item remote
    ```

    Alternatively you can loop the accounts from the content of accounts.json:

    ```shell
    for account_name in $(jq -r '.Accounts[].Name' < ./accounts.json); do
      if [ "${account_name}" != "hub" ]; then
        ./deploy-cfn.sh \
        --account "${account_name}" \
        --extra-vars aws_region=${AWS_DEFAULT_REGION} \
        --action deploy \
        --dry-run false \
        --item remote
        ```
      fi
    done
