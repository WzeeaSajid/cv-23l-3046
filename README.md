# Host Your CV on AWS

**Name:** Wzeea Sajid  
**Roll number:** 23L-3046  
**Course:** cloud  
**Region:** us-east-1 (N. Virginia)

| What | Address |
| --- | --- |
| EC2 site | http://174.129.189.230 |
| Lambda site | https://dgkkmifpplm7wmwimmux7msdji0ruqpc.lambda-url.us-east-1.on.aws/ |

## 1. Architecture

```
                         +-----------------------------------+
                         |  S3 bucket: cv-23l-3046 (PRIVATE) |
                         |  site/index.html                  |
                         |  site/style.css                   |
                         |  site/cv.pdf                      |
                         |  Block Public Access: ON          |
                         |  Versioning: ON                   |
                         +-----------------+-----------------+
                                           ^
              s3:GetObject, s3:ListBucket  |   s3:GetObject (site/* only)
              (role cv-ec2-role-23l-3046)  |   (role cv-lambda-role-23l-3046)
                          +----------------+----------------+
                          |                                 |
              +-----------+-----------+         +-----------+-----------+
              | EC2 cv-ec2-23l-3046   |         | Lambda cv-func-23l-3046|
              | Apache + sync-cv.sh   |         | Python, function URL   |
              | (systemd timer, 2 min)|         | (auth type NONE)       |
              +-----------+-----------+         +-----------+-----------+
                          ^                                 ^
                    HTTP :80                          HTTPS (function URL)
                          |                                 |
                          +----------------+----------------+
                                           |
                                       Visitor
                                    (browser / curl)

   Direct request to the S3 object URL  ->  403 AccessDenied
```

**Path A (EC2):** A visitor's browser sends an HTTP request on port 80 to the instance's public IPv4 address, where Apache serves the files from `/var/www/html`. Those files were copied from the `site/` prefix of the private bucket by `sync-cv.sh` using the instance role, which runs at boot and then every 2 minutes, and which swaps the footer placeholder for `EC2` and the instance ID.

**Path B (Lambda):** A visitor's browser sends an HTTPS request to the public function URL, which invokes the function with the request path. The function reads the matching object from `site/` in the bucket using its execution role and returns it (base64 for the PDF), replacing the footer placeholder with `Lambda` and the function name.

## 2. Repository layout

```
README.md
collect-evidence.sh
evidence.txt
site/      index.html, style.css, cv.pdf
ec2/       user-data.sh, sync-cv.sh
lambda/    lambda_function.py
iam/       ec2-trust.json, ec2-permissions.json,
           lambda-trust.json, lambda-permissions.json
```

## 3. Access denied from the instance

From a shell on the instance (`i-014d8d1c499b63e0f`), trying to delete and overwrite an object in the bucket:

```
[ec2-user@ip-172-31-25-122 ~]$ echo "test" > /tmp/x.txt
aws s3 rm s3://cv-23l-3046/site/index.html --region us-east-1
aws s3 cp /tmp/x.txt s3://cv-23l-3046/site/index.html --region us-east-1
delete failed: s3://cv-23l-3046/site/index.html An error occurred (AccessDenied) when calling the DeleteObject operation: User: arn:aws:sts::309615787408:assumed-role/cv-ec2-role-23l-3046/i-014d8d1c499b63e0f is not authorized to perform: s3:DeleteObject on resource: "arn:aws:s3:::cv-23l-3046/site/index.html" because no identity-based policy allows the s3:DeleteObject action
upload failed: ../../tmp/x.txt to s3://cv-23l-3046/site/index.html An error occurred (AccessDenied) when calling the PutObject operation: User: arn:aws:sts::309615787408:assumed-role/cv-ec2-role-23l-3046/i-014d8d1c499b63e0f is not authorized to perform: s3:PutObject on resource: "arn:aws:s3:::cv-23l-3046/site/index.html" because no identity-based policy allows the s3:PutObject action
```

## 4. Sync log (last 10 lines of /var/log/cv-sync.log)

```
2026-10-24T16:11:23Z sync OK instance=i-014d8d1c499b63e0f
2026-10-24T16:13:23Z sync OK instance=i-014d8d1c499b63e0f
2026-10-24T16:15:23Z sync OK instance=i-014d8d1c499b63e0f
2026-10-24T16:17:23Z sync OK instance=i-014d8d1c499b63e0f
2026-10-24T16:19:23Z sync OK instance=i-014d8d1c499b63e0f
2026-10-24T16:21:23Z sync OK instance=i-014d8d1c499b63e0f
2026-10-24T16:23:24Z sync OK instance=i-014d8d1c499b63e0f
2026-10-24T16:25:24Z sync OK instance=i-014d8d1c499b63e0f
2026-10-24T16:27:24Z sync OK instance=i-014d8d1c499b63e0f
2026-10-24T16:29:24Z sync OK instance=i-014d8d1c499b63e0f
```

## 5. Written answers

**1. Why do the instance and the function use roles instead of access keys? What could go wrong if the keys were in the user data?**  
A role gives the instance or function short-lived credentials that AWS creates and rotates automatically, so nothing permanent is stored anywhere. An access key is a long-lived secret that works from any computer until someone revokes it. User data is plain text that is kept with the instance and can be read from the instance itself and by anyone allowed to describe it. If the keys were in the user data, they could leak through the console, a copied script or a public GitHub repo, and an attacker could then use them from anywhere with all the permissions of that key.

**2. Someone pastes the S3 address of index.html into a browser. What do they see, and which setting causes that?**  
They see an "Access Denied" error page (HTTP 403) instead of the CV. This happens because all four Block Public Access settings are on and the bucket has no bucket policy or ACL that grants anything to everyone. The request is anonymous, so S3 has no permission that lets it through. Only the two IAM roles can read the objects.

**3. Explain in your own words the permission on the function URL that lets anyone call it. Why is that acceptable for the function but not for the bucket?**  
When I created the function URL with auth type NONE, the console added a resource-based policy statement to the function. It allows any principal (`*`) to run `lambda:InvokeFunctionUrl`, but only when the URL's auth type is NONE, so visitors don't need to sign requests. This is fine for the function because the code decides what is returned, so a visitor can only get the three public CV files, and the role limits it to `GetObject` on `site/*`. A public bucket would let people read the raw storage directly, bypassing my code, and a mistake in its policy could expose or even allow changes to every object.

**4. Compare the two paths. What do you pay for when nobody visits the site? What happens if the traffic grows a hundred times?**  
The EC2 instance runs all day, so I pay for it (and its disk and public IPv4 address) even with no visitors. With Lambda I pay nothing when there are no requests, apart from small storage costs such as logs, and S3 storage is paid in both cases. If traffic grew a hundred times, a single `t3.micro` could become slow or overloaded and I would need a bigger instance or more instances behind a load balancer. Lambda runs more copies of the function automatically (within account limits), and the cost grows with the number of requests.

**5. You delete the EC2 instance. What do you lose and what do you still have?**  
I lose the running server, its public IP address (it is not an Elastic IP, so a new instance gets a different one), the Apache install, the web root copy of the site and the local log `/var/log/cv-sync.log`. I still have the S3 bucket with all the files and versions, both IAM roles and their policies, the security group and key pair, and the Lambda site, which keeps working. The repository also keeps `user-data.sh` and `sync-cv.sh`, so I can launch a new instance and get the same site again.

## 6. Evidence

`collect-evidence.sh` takes the bucket name, the EC2 address and the Lambda address and writes `evidence.txt`:

```
./collect-evidence.sh cv-23l-3046 http://174.129.189.230 https://dgkkmifpplm7wmwimmux7msdji0ruqpc.lambda-url.us-east-1.on.aws/
```

With any other number of arguments it prints a usage line and exits with code 1.

## 7. Sources and help

- AWS documentation for S3, IAM, EC2, Lambda function URLs and systemd timers.
- I drafted the scripts and README, and I tested and adapted them in my own AWS account.
