enum Ensure {
    Present
    Absent
}

[DscResource()]
class MasterNode {
    [DscProperty(Mandatory)]       [string]    $Ensure
    [DscProperty(Mandatory)]       [string]    $Key
    [DscProperty(Mandatory)]       [string]    $ValueTrue
    [DscProperty(Mandatory)]       [string]    $ValueFalse
    [DscProperty(Key)]             [string]    $MyId
    [DscProperty(NotConfigurable)] [string]    $MyValue
    [DscProperty(NotConfigurable)] [string]    $MasterCount
    [DscProperty(NotConfigurable)] [string]    $MasterId
    [DscProperty(NotConfigurable)] [string]    $StackName
    [DscProperty(NotConfigurable)] [string]    $ELB
    [DscProperty(NotConfigurable)] [string[]]  $Nodes
    [DscProperty(NotConfigurable)] [hashtable] $TagStatus
    [MasterNode]Get() {
        $this.GetTheBasic()
        $this.TagStatus = $this.GetTagStatus($this.Nodes, $this.Key, $this.ValueTrue)
        $this.MasterId = $this.TagStatus.ListOfMasterNode
        $this.MasterCount = $this.TagStatus.MasterCount
        return $this
    }
    [void]Set() {
        $this.GetTheBasic()
        if ($this.Ensure -eq [Ensure]::Present) {
            if ($this.SetMasterNode()) {
                Write-Verbose "SetMasterNode completed"
            }
            else {
                Write-Verbose "SetMasterNode failed"
            }
        }
    }
    [bool]Test() {
        $this.GetTheBasic()
        $Status = $this.GetTagStatus($this.Nodes, $this.Key, $this.ValueTrue)
        Write-Verbose "Current TagStatus:`n$Status"
        if (($Status.MasterCount -ne 1) -or `
            !$this.MasterId -or `
            ($this.MyId -notin $this.Nodes)) {
            return $false
        }
        else {
            return $true
        }
    }
    [string]GetELB() {
        return (Get-CFNStackResourceList $this.StackName | Where-Object {
                    $_.ResourceType -eq 'AWS::ElasticLoadBalancing::LoadBalancer'
                }).PhysicalResourceId
    }
    [string[]]GetNodes() {
        return (Get-ELBLoadBalancer $this.ELB).Instances.InstanceId
    }
    [hashtable]GetATagFromInstance([string]$InstanceId, [string]$Key) {
        $Filter = @{ Name = 'resource-id'; Values = $InstanceId }
        $Tag = Get-EC2Tag -Filter $Filter | Where-Object {
            $_.Key -eq $Key
        }
        return @{
            Key = $Tag.Key
            Value = $Tag.Value
        }
    }
    [hashtable]GetTagStatus([string[]]$InstanceIds, [string]$Key, [string]$Value) {
        $Total = $this.Nodes.Count
        $Count = 0
        $ListOfMasterNode = @()
        foreach ($i in $InstanceIds) {
            if ((Get-EC2Instance $i).Instances.State.Name.Value -ne 'running') {
                $Total--
                continue
            }
            $Tag = $this.GetATagFromInstance($i, $this.Key)
            if ($Tag.Value -eq $Value) {
                $ListOfMasterNode += $i
                $Count++
            }
        }
        return @{
            Key = $Key
            Value = $Value
            Total = $Total
            MasterCount = $Count
            ListOfMasterNode = $ListOfMasterNode
        }
    }
    [void]GetTheBasic() {
        $this.StackName = ($this.GetATagFromInstance($this.MyId, 'aws:cloudformation:stack-name')).Value
        $this.ELB = $this.GetELB()
        $this.Nodes = $this.GetNodes()
        $this.MyValue = ($this.GetATagFromInstance($this.MyId, $this.Key)).Value
    }
    [bool]SetMasterNode() {
        $Return = $false
        
        $TagTrue = @{ Key = $this.Key; Value = $this.ValueTrue }
        $TagFalse = @{ Key = $this.Key; Value = $this.ValueFalse }
        
        do {
            $this.TagStatus = $this.GetTagStatus($this.Nodes, $this.Key, $this.ValueTrue)
            switch ($this.TagStatus.MasterCount) {
                0 {
                    try {
                        Write-Verbose "Applying $TagTrue"
                        New-EC2Tag -Resource $this.MyId -Tag $TagTrue -ErrorAction Stop
                        $Return = $true
                    }
                    catch { $Return = $false }
                    break
                }
                1 {
                    try {
                        $MyTag = $this.GetATagFromInstance($this.MyId, $this.Key)
                        if ($MyTag.Value -ne $TagTrue.Value) {
                            Write-Verbose "Applying $TagTrue"
                            New-EC2Tag -Resource $this.MyId -Tag $TagFalse -ErrorAction Stop
                        }
                        $Return = $true
                    }
                    catch { $Return = $false }
                    break
                }
                { $_ -gt 1 } {
                    try {
                        for ($i = $this.TagStatus.MasterCount; $i -gt 1; $i--) {
                            Write-Verbose "Removing $TagTrue"
                            Remove-EC2Tag -Resource $this.TagStatus.ListOfMasterNode[$i-1] `
                                          -Tag $TagTrue -Force
                        }
                        Write-Verbose "Applying $TagFalse"
                        New-EC2Tag -Resource $this.MyId -Tag $TagFalse -Force
                        $Return = $true
                    }
                    catch { $Return = $false }
                    break
                }
            }
        } while ($this.TagStatus.MasterCount -ne 1)
        return $Return
    }
}
