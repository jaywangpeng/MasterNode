# MasterNode
This is a class based PowerShell DSC module to elect a master node in a AWS EC2 cluster which is built with ELB and ASG.


## Requirements
- PowerShell 5.0
- Windows Server Core AMI (2012R2, 2016, or 2019)
- AWS EC2 Instances, Elastic Load Balancer (Network Load Balancer)


## Setup
The following steps must all be done on all instances in the cluster.
This module can be installed in any module path in one of `$ENV:PSModulePath` on each instance of the cluster.
For example:
```PowerShell
git clone https://github.com/jaywangpeng/MasterNode.git "$Env:ProgramFiles\WindowsPowerShell\Modules"
Import-Module MasterNode
```


### LCM for PowerShell DSC
We need to configure LocalConfigurationManager which is the engine of DSC.
```PowerShell
    function Set-LCM {
        [DSCLocalConfigurationManager()]
        configuration LCM {
            Node 'localhost' {
                Settings {
                    RefreshMode = 'ApplyAndAutoCorrect'
                }
            }
        }
        LCM
        Set-DscLocalConfigurationManager LCM -Force
    }
    Set-LCM
```


### Run the DSC
The following function can be put into `user-data` of the instances to invoke the DSC at the bootup.
`Key`, `ValueTure`, and `ValueFalse` can be defined in the DSC and will be used in instance tags.
This example uses `ScheduledTask`, `Yes`, and `No` as these values.
```PowerShell
    function Invoke-DscMasterNode {
        [CmdletBinding()]
        param ()
        configuration MasterNode {
            Import-DscResource -ModuleName 'MasterNode'
            MasterNode 'MasterNode' {
                Ensure     = 'Present'
                Key        = 'ScheduledTask'
                ValueTrue  = 'Yes'
                ValueFalse = 'No'
                #This is AWS default meta-data URL
                MyId = Invoke-RestMethod 'http://169.254.169.254/latest/meta-data/instance-id'
            }
        }
        # Compile the DSC to MOF file
        MasterNode
        # Run the DSC
        Start-DSCConfiguration -Path '.\MasterNode\' -Force -Wait -Verbose -ErrorAction Stop
    }
    Invoke-DscMasterNode -Verbose
```


### Tasks you want only the master node to run
Whether it's a scheduled task or a deployment script, add the following to the **beginning** of your script.
Then only the master will run it while other instances will bypass.
An example for Scheduled Task script (The Tag key and value should match whatever is defined in your DSC)
```PowerShell
    $Id = Invoke-RestMethod 'http://169.254.169.254/latest/meta-data/instance-id'
    $Filter = @{ Name = 'resource-id'; Values = $Id }
    $Tag = Get-EC2Tag -Filter $Filter | Where-Object { $_.Key -eq 'ScheduledTask' }
    if ($Tag.Value -ne 'Yes') { return }
    # Non-master instances will stop executing further but master instance will continue
    # Your actual script below
```
