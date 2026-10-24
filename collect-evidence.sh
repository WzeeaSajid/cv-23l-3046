#!/bin/bash
# Usage: ./collect-evidence.sh <bucket-name> <ec2-address> <lambda-address>
if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <bucket-name> <ec2-address> <lambda-address>"
  exit 1
fi

BUCKET="$1"
EC2_ADDR="$2"
LAMBDA_ADDR="$3"
OUT="evidence.txt"
REGION="${AWS_REGION:-us-east-1}"

# Resource names follow the lab's pattern (the bucket is cv-<roll>)
SUFFIX="${BUCKET#cv-}"
EC2_ROLE="cv-ec2-role-${SUFFIX}"
LAMBDA_ROLE="cv-lambda-role-${SUFFIX}"
FUNC="cv-func-${SUFFIX}"
INSTANCE_NAME="cv-ec2-${SUFFIX}"
SG_NAME="cv-sg-${SUFFIX}"

case "$EC2_ADDR" in http*) ;; *) EC2_ADDR="http://${EC2_ADDR}" ;; esac
case "$LAMBDA_ADDR" in http*) ;; *) LAMBDA_ADDR="https://${LAMBDA_ADDR}" ;; esac
EC2_ADDR="${EC2_ADDR%/}"
LAMBDA_ADDR="${LAMBDA_ADDR%/}"

: > "$OUT"

section() { printf '\n== %s ==\n' "$1" >> "$OUT"; }

# Run a command, append its output, note a failure and carry on
run() {
  if ! "$@" >> "$OUT" 2>&1; then
    echo "[FAILED] $*" >> "$OUT"
  fi
}

check_url() {
  local result
  result=$(curl -s -o /dev/null -m 15 -w "%{http_code} %{content_type}" "$1" 2>&1) || result="curl failed"
  echo "$1 -> $result" >> "$OUT"
}

section caller
run aws sts get-caller-identity --region "$REGION"

section public-access
run aws s3api get-public-access-block --bucket "$BUCKET"

section versioning
run aws s3api get-bucket-versioning --bucket "$BUCKET"

section objects
run aws s3 ls "s3://${BUCKET}/" --recursive

section ec2-policy
run aws iam get-role-policy --role-name "$EC2_ROLE" --policy-name cv-ec2-s3-read

section lambda-policy
run aws iam list-attached-role-policies --role-name "$LAMBDA_ROLE"
run aws iam get-role-policy --role-name "$LAMBDA_ROLE" --policy-name cv-lambda-s3-read

section security-group
run aws ec2 describe-security-groups --region "$REGION" \
  --filters "Name=group-name,Values=${SG_NAME}" \
  --query "SecurityGroups[].IpPermissions" --output json

section instance
run aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:Name,Values=${INSTANCE_NAME}" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].{InstanceId:InstanceId,Type:InstanceType,IMDSv2:MetadataOptions.HttpTokens,Profile:IamInstanceProfile.Arn,PublicIp:PublicIpAddress}" \
  --output json

section endpoints
check_url "${EC2_ADDR}/"
check_url "${EC2_ADDR}/style.css"
check_url "${EC2_ADDR}/cv.pdf"
check_url "${LAMBDA_ADDR}/"
check_url "${LAMBDA_ADDR}/style.css"
check_url "${LAMBDA_ADDR}/cv.pdf"
check_url "${LAMBDA_ADDR}/anything"
check_url "https://${BUCKET}.s3.amazonaws.com/site/index.html"

section lambda-logs
if logs=$(aws logs tail "/aws/lambda/${FUNC}" --since 1d --region "$REGION" 2>&1); then
  echo "$logs" | tail -n 15 >> "$OUT"
else
  echo "[FAILED] aws logs tail" >> "$OUT"
  echo "$logs" >> "$OUT"
fi

section log-retention
run aws logs describe-log-groups --region "$REGION" \
  --log-group-name-prefix "/aws/lambda/${FUNC}" \
  --query "logGroups[].{name:logGroupName,retentionInDays:retentionInDays}" \
  --output json

echo DONE