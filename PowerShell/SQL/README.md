## Setting up SQL Server on your local machine

#### Dependancies: 
* Docker Desktop - download [here](https://hub.docker.com/editions/community/docker-ce-desktop-windows/) or install through chocolatey: `choco install docker-desktop` 
* Sqlpackage.exe - download [here](https://docs.microsoft.com/en-us/sql/tools/sqlpackage-download?view=sql-server-ver15) or install through chocolatey`choco install sqlpackage --version=18.5.1`.  Make sure that SqlPackage.exe is added to your path. Normally it is installed to `C:\Program Files\Microsoft SQL Server\150\DAC\bin`
* Powershell 7.x - installation instructions [here](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell?view=powershell-7.1)

*NOTE: You should be able to use most of this on Windows or Mac but there are a few items that are Windows specific.*

1. Download the sql server instance. Run the following command: 
`docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=sa_password!!123" -p 1433:1433 -d mcr.microsoft.com/mssql/server:2017-latest`
OR
`docker-compose up -d`

    Now you should be able to connect to the server (localhost) with sa (the password can be found in the docker-compose file)

2. Setting up the server. Now that the server is installed you need to do a few more things to get it ready.  
A. - create a login  
B. - enable Contained Database Authentication  
C. - download data from your azure database  
D. - import that data into your local instance  

    If you have PowerShell installed you can run `Setup-Sql.ps1` and it will take care of all of this for you.  Otherwise you will need to do it manually. 

### Manual setup
Connect to the server using your prefered SQL Client and create a login  by running the following queries with your preferred login and password.

```sql
CREATE LOGIN loginName WITH PASSWORD='strong_password()', DEFAULT_DATABASE=[master], CHECK_EXPIRATION=OFF, CHECK_POLICY=OFF
GO
ALTER SERVER ROLE [sysadmin] ADD MEMBER loginName
GO    
SP_CONFIGURE 'show advanced options', 1
GO
RECONFIGURE
GO
SP_CONFIGURE 'CONTAINED DATABASE AUTHENTICATION', 1
GO
RECONFIGURE
GO
SP_CONFIGURE 'show advanced options', 0 
GO
RECONFIGURE
GO
```


To get the data from your azure database you will have to download it into a bacpac file. You can do that using the following command: 

```
SqlPackage.exe /a:Export /tf:Export.bacpac /scs:"Server=tcp:myserver.database.windows.net,1433;Initial Catalog=MyDb;Persist Security Info=False;User ID=ImaDbUser;Password=<secret_password>;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;" /ua:False
```

Once that has completed running you can then import it into a new database called LocalDb on your local server. To import the data you will need to run the the following command:

```
SqlPackage /a:Import /sf:Export.bacpac /tsn:tcp:localhost /tdn:LocalDb /tu:sa /tp:sa_password!!123
```


### Next Steps
#### Common Docker commands
To check if the instance is running you can run `docker ps` - this will display any docker processes that are running. 

If you don't see any docker processes you can try `docker ps -a` - this will display any docker containers that are stopped. 

To start the docker container: `docker start <container_name>`

To stop the docker container: `docker stop <container_name>`

More info: https://hub.docker.com/_/microsoft-mssql-server


### Troubleshooting

#### PowerShell setup
The easiest way to install PowerShell 7.x is by running `dotnet tool install --global PowerShell` - this does require that you have the [.Net Core 5.0 SDK](https://dotnet.microsoft.com/download/dotnet/5.0) installed.

#### Missing modules
The setup.ps1 script should install all the modules it needs but if it gives you an error you can try installing the modules manually
* PowerShell SqlServer Module - You can install this by running `Install-Module -Name SqlServer`
* Azure PowerShell Module - installation instructions can be found [here](https://docs.microsoft.com/en-us/powershell/azure/install-az-ps?view=azps-5.1.0)

