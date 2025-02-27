# Lambda Version Cleaner

Lambda Version Cleaner is a project designed to manage and clean up old versions of AWS Lambda functions, ensuring that only a specified number of recent versions are retained. This helps in managing the storage and keeping the Lambda functions organized.

## Table of Contents

- [Resources](#resources)
- [Getting Started](#getting-started)
- [Usage](#usage)
- [Contributing](#contributing)
- [License](#license)

## Resources

This project uses Terraform to provision the necessary AWS resources and a Python script to handle the version cleanup process. The following resources are created by the `main.tf` file:

- **IAM Role and Policy**: An IAM role with a policy that allows the Lambda function to create log groups, log streams, put log events, list Lambda functions, list versions by function, and delete functions.

- **S3 Bucket**: An S3 bucket to store the Lambda function code.

- **Lambda Function**: A Lambda function that performs the version cleanup process. The function is configured with environment variables to specify the AWS region, the number of versions to keep, a regex pattern to match function names, and a comma-separated list of specific function names.

- **CloudWatch Event Rule**: A CloudWatch Event rule that triggers the Lambda function based on a specified schedule (default is once per day at 3 AM UTC).

- **CloudWatch Event Target**: A CloudWatch Event target that specifies the Lambda function to be invoked by the CloudWatch Event rule.

- **Lambda Permission**: A permission that allows CloudWatch Events to invoke the Lambda function.

### How It Works

The CloudWatch Event rule is configured to run the Lambda function once per day at 3 AM UTC. When the rule triggers, it invokes the Lambda function, which then lists all Lambda functions in the specified region (or the functions specified by the environment variables). For each function, the Lambda function lists all versions, sorts them in descending order, and deletes the older versions, keeping only the specified number of recent versions.

This automated process helps in managing the storage and keeping the Lambda functions organized by removing old and unnecessary versions.

## Getting Started

### Prerequisites

- [Terraform](https://www.terraform.io/downloads.html) (version >= 0.14.9)
- [Python](https://www.python.org/downloads/) (version >= 3.9)
- [AWS CLI](https://aws.amazon.com/cli/) configured with appropriate credentials
- [Make](https://www.gnu.org/software/make/)

### Installation

1. Clone the repository:
    ```sh
    git clone https://github.com/wsgomes/lambda-version-cleaner.git
    cd lambda-version-cleaner
    ```

2. Initialize Terraform:
    ```sh
    make init
    ```

3. Deploy all resources:
    ```sh
    make apply
    ```

## Usage

### Terraform Commands

- Initialize Terraform:
    ```sh
    make init
    ```

- Plan the Terraform deployment:
    ```sh
    make plan
    ```

- Apply the Terraform deployment:
    ```sh
    make apply
    ```

- Destroy the Terraform deployment:
    ```sh
    make destroy
    ```

### Environment Variables

You can configure the Lambda function using the following environment variables:

- `THIS_AWS_REGION`: The AWS region from where Lambda functions will be queried. If not provided, the default region from the running environment will be used.
- `VERSIONS_TO_KEEP`: The number of most recent versions to retain for each Lambda function.
- `FUNCTION_NAME_PATTERN`: A regex pattern to match the function names to be processed.
- `FUNCTION_NAMES`: A comma-separated list of specific function names to be processed.

If neither `FUNCTION_NAME_PATTERN` nor `FUNCTION_NAMES` is provided, the code will process all functions available in the specified region.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request for any improvements or bug fixes.

## License

This project is licensed under the MIT License. See the LICENSE file for details.
