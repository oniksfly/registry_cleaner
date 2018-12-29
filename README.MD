# Usage

## Params

- `host`: Registry host name, required. Example: `https://registry.exmpl.com`.
- `port`: Registry port, default value is `5000`.
- `repository`: Registry repository name to clean old build. If no name passed the util will return repositories list.
- `tags_count`: Define how many builds to store, default value is `5`.
- `auth_login`: Basic auth login if server required it.
- `auth_password`: Basic auth passwor if server required it.

## List repositories
`./registry_cleaner.rb --host=https://registry.exmpl.com`

## Clean old builds
Save 4 latest builds for repository with name `name`: `./registry_cleaner.rb --host=https://registry.exmpl.com --repository=name --tags_count=4`

## Collect garbage
To clean disck space don't forget to run registry gabage collector. For docker container: `/bin/registry garbage-collect /etc/docker/registry/config.yml`.