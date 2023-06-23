# Creating the project property

Start making the project shared property for all requests.

## Overview

To start integrating RequestDL into your project, we recommend creating an object that configures the shared properties for all requests to a host.

For example, let's build an application that consumes the Github API. In the [documentation](https://docs.github.com/en/rest), it specifies that the `Accept` header should always be set to `application/vnd.github+json`, and the `X-GitHub-Api-Version` header should be set to `2022-11-28`, which is the latest version of the API. Additionally, all calls should be made to `https://api.github.com`.

### The project property

To implement these specifications for the Github API, we need to create the following object:

```swift
import RequestDL

struct GithubAPI: Property {

    var body: some Property {
        BaseURL("api.github.com")
        
        AcceptHeader("application/vnd.github+json")
        CustomHeader(name: "X-GitHub-Api-Version", value: "2022-11-28")
    }
}
```

#### Authentication

The Github documentation provides various authentication methods, which are not covered in this example. For educational purposes, let's focus on consuming a Github endpoint that requires the `Authorization: Bearer ***` header.

To accomplish this, we can leverage the `GithubAPI` object with the following implementation:

- If you want to provide the token externally:

    ```swift
    import RequestDL

    struct GithubAPI: Property {

        let token: String?

        var body: some Property {
            BaseURL("api.github.com")
            
            AcceptHeader("application/vnd.github+json")
            CustomHeader(name: "X-GitHub-Api-Version", value: "2022-11-28")

            if let token {
                Authorization(.bearer, token: token)
            }
        }
    }
    ```

- If you want to consume a service:

    ```swift
    import RequestDL

    struct GithubAPI: Property {

        var body: some Property {
            BaseURL("api.github.com")
            
            AcceptHeader("application/vnd.github+json")
            CustomHeader(name: "X-GitHub-Api-Version", value: "2022-11-28")

            if let token = GithubService.shared.token {
                Authorization(.bearer, token: token)
            }
        }
    }
    ```

Of course, there are multiple options to achieve this, and we are only exploring a few valid approaches here.

#### ContentType

Another commonly used aspect in requests is ``RequestDL/ContentType``. The Github case is an excellent example since it requires a custom value that deviates from the existing standard value in the library, `application/json`.

To achieve this, you need to configure a separate file to extend ``RequestDL/ContentType`` as follows:

```swift
import RequestDL

extension ContentType {

    static let githubJSON = ContentType("application/vnd.github+json")
}
```

This way, you can use this content type whenever necessary throughout your code.

## Next steps

Now that you have made these initial configurations, there are, of course, other aspects to explore and utilize according to the specific needs of each application. However, this is the most basic example of getting started, and you are now ready to move on to the next steps.
