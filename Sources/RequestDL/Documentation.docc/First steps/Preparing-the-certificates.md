# Preparing the Certificates

Set up all the necessary certificates to ensure secure requests.

## Overview

The most important configuration required in any application is to apply some security protocols, such as TLS, mTLS, or PSK. Here we will provide detailed instructions on the most basic way to implement these protocols directly in your application.

We are sharing two methods to obtain server certificates to help you explore the available resources. Additionally, obtaining a server certificate is quite easy nowadays.

### Obtaining the Certificate 

#### via Browser

In this example, we will obtain the DER certificates from the `api.github.com` server for our application.

One crucial point is to download the entire certificate hierarchy because when configuring it in RequestDL or other frameworks like URLSession, the application will compare all the received certificates.

1. Access `https://api.github.com` and click on the padlock.

    ![Screenshot of Safari showing the loaded URL with the padlock highlighted](der.github.1.png)

2. Click on **Show Certificate**.

    ![Screenshot of Safari showing the certificate for the URL with the "Show Certificate" button highlighted](der.github.2.png)

3. Select **\*.github.com** and drag the certificate to your desktop.

    ![Screenshot of Safari showing the certificates in use with the certificate icon highlighted](der.github.3.png)

4. Repeat the same process for **DigiCert TLS...**.

    ![Screenshot of Safari showing the certificates in use with the certificate icon highlighted](der.github.4.png)

5. Repeat the same process for **DigiCert Global...**.

    ![Screenshot of Safari showing the certificates in use with the certificate icon highlighted](der.github.5.png)

6. Drag the certificates into the **Resources** folder of your project or module.

In this example, we downloaded the entire certificate hierarchy from the server. However, we have the option to use ``RequestDL/DefaultTrusts`` together with ``RequestDL/AdditionalTrusts`` to achieve a similar result.

- Note: It is recommended to always convert the certificates to PEM format, as it allows you to combine them into a single file for use anywhere.

#### via Terminal

Another method is to use the `openssl` command in your terminal. By using the command below, you can obtain the certificate in **PEM** format.

1. Open the terminal.

2. Enter the command `openssl s_client -connect api.github.com:443`.

3. Look for the `BEGIN CERTIFICATE` and `END CERTIFICATE` in the output:
    ```
    -----BEGIN CERTIFICATE-----
    ***
    ***
    ***
    -----END CERTIFICATE-----
    ```

4. Copy the pattern above and paste it into a file.

5. Save it as **\*.github.com.pem**.

6. Drag the generated file into the **Resources** folder of your project or module.

In this example, we only downloaded the main server certificate without downloading the complete hierarchy. You can find other examples in the community explaining how to do this via the terminal.

### Configuring GithubAPI

If you have read **[Creating the project property](<doc:Creating-the-project-property>)**, the configuration example we will be using is a continuation of the GithubAPI implementation.

#### Using DER Certificates Individually

```swift 
import RequestDL

struct GithubAPI: Property {

    var body: some Property {
        // Previous code
        SecureConnection {
            Trusts {
                Certificate("DigiCert Global...", format: .der)
                Certificate("DigiCert TLS...", format: .der)
                Certificate("*.github.com", format: .der)
            }
        }
    }
}
```

#### Using PEM Certificates

```swift 
import RequestDL

struct GithubAPI: Property {

    var body: some Property {
        // Previous code
        SecureConnection {
            Trusts {
                Certificate("*.github.com", format: .pem)
            }
        }
    }
}
```

## Next steps

These were some basic examples of how to configure certificates to validate the server during a request. By doing this, you will be using TLS security in your network layer.

Although it may not be the most secure option, we also support implementing mTLS or PSK. Continue exploring our documentation for more relevant information.
