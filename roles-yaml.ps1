param(
    [string]$principalType,
    [string]$principalName,
    [string]$scopeType,
    [string]$managementGroup,
    [string]$subscriptionName,
    [string]$resourceGroupName,
    [string]$resourceType,
    [string]$resourceName,
    [string]$roleName,
    [string]$codapp,
    [string]$grupodered,
    [string]$ambiente,
    [string]$assignmentType,
    [string]$startTime,
    [string]$endTime
)

$rolesRestringidos = @(
   "Owner",
   "Contributor",
   "User Access Administrator",
   "Reservations Administrator",
   "Access Review Operator Service Role",
   "Role Based Access Control Administrator",
   "Service Group Contributor",
   "Administrador IBM Cloud",
   "Environment Automation",
   "Environment Automation II",
   "Rol Administrador de Accesos",
   "Rol Administrador de Accesos PIM",
   "Administrador Modelo Soporte",
   "Environment Operator APIM",
   "Rol Modificar NSG SOAR",
   "Rol Networking Whitelist - Ambientes Previos",
   "Developer Environment Operator",
   "Environment Operator",
   "Reader Environment Certi",
   "Reader Certi QA"
)

Write-Host "=== AZURE ROLE ASSIGNMENT TOOL ===" -ForegroundColor Green

# Verificar conexión a Azure
try {
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "No estás conectado a Azure. Ejecutando Connect-AzAccount..." -ForegroundColor Yellow
        Connect-AzAccount
    }
    Write-Host "Conectado a Azure - Tenant: $($context.Tenant.Id)" -ForegroundColor Green
}
catch {
    Write-Error "Error al conectar con Azure: $($_.Exception.Message)"
    exit 1
}

$scopePath = ""
$idgrupodered = $null

switch ($scopeType) {
    "Management Group" {
        $mgName = $managementGroup
        $scopePath = "/providers/Microsoft.Management/managementGroups/$mgName"

        if (-not $mgName) { throw "No se encontró el Nombre del Management Group." }
        if ($ambiente -ne "Producción") { throw "El ambiente debe ser productivo para este tipo de solicitud." }

        if ($principalType -eq "Service Principal") {
            $sp = Get-AzADServicePrincipal -DisplayName $principalName -ErrorAction SilentlyContinue
            if (-not $sp) { throw "El Service Principal '$principalName' no existe en Azure AD." }
            if ($principalName -notmatch "PRO") {
                throw "El Service Principal '$principalName' no es de producción. Favor de ingresar correctamente el Service Principal."
            }
            if ($rolesRestringidos -contains $roleName) {
                throw "El Rol '$roleName' no está permitido solicitarlo por este medio, se procede a cancelar la solicitud"
            }
            $idsp = $sp.Id
            $assignments = Get-AzRoleAssignment -ObjectId $idsp -Scope $scopePath
            $Assigned = $assignments | Where-Object { $_.RoleDefinitionName -eq $roleName }
            if ($Assigned) {
                Write-Host "El Service Principal '$principalName' ya tiene el rol '$roleName' asignado a nivel de Management Group."
            }
            if ($assignmentType -eq "Permanente") {
                Write-Host "Asignando rol permanente en el Management Group..."
                New-AzRoleAssignment -ObjectId $idsp -RoleDefinitionName $roleName -Scope $scopePath
                Write-Host "Se agregó el rol '$roleName' permanente correspondiente al Service Principal '$principalName' en el management group '$mgName'"
            }
            elseif ($assignmentType -eq "Temporal") {
                $horaPeruTextoini = $startTime
                $horaPeruTextofin = $endTime
                $horaUTCini = [datetime]::ParseExact($horaPeruTextoini, "yyyy-MM-dd HH:mm", $null)
                $horaUTCini2 = [datetime]::SpecifyKind($horaUTCini, [System.DateTimeKind]::Utc)
                $horaUTCfin = [datetime]::ParseExact($horaPeruTextofin, "yyyy-MM-dd HH:mm", $null)
                $horaUTCfin2 = [datetime]::SpecifyKind($horaUTCfin, [System.DateTimeKind]::Utc)
                $zonaPeru = [System.TimeZoneInfo]::FindSystemTimeZoneById("SA Pacific Standard Time")
                $horaPeruini = [System.TimeZoneInfo]::ConvertTimeFromUtc($horaUTCini, $zonaPeru)
                $horaPerufin = [System.TimeZoneInfo]::ConvertTimeFromUtc($horaUTCfin, $zonaPeru)
                $guid = [guid]::NewGuid().ToString()
                $startTimeISO = Get-Date $horaUTCini2 -Format o
                $endTimeISO = Get-Date $horaUTCfin2 -Format o
                $rolId = (Get-AzRoleDefinition -Name $roleName).Id
                $Justification = "Asignación de rol temporal por medio de GitHub Actions"

                New-AzRoleAssignmentScheduleRequest -Name $guid `
                    -Scope $scopePath `
                    -ExpirationType AfterDateTime `
                    -PrincipalId $idsp `
                    -RequestType AdminAssign `
                    -RoleDefinitionId "/providers/Microsoft.Authorization/roleDefinitions/$rolId" `
                    -ScheduleInfoStartDateTime $startTimeISO `
                    -ExpirationEndDateTime $endTimeISO `
                    -Justification $Justification

                Write-Host "Se agregó el rol '$roleName' temporal correspondiente al Service Principal '$principalName' en el management group '$mgName' (Vigencia: $($horaPeruini.ToString('dd/MM/yyyy HH:mm')) hasta $($horaPerufin.ToString('dd/MM/yyyy HH:mm')) )"
            }
        }
        else {
            $group = Get-AzADGroup -DisplayName $grupodered -ErrorAction SilentlyContinue
            if (-not $group) { throw "El grupo de red '$grupodered' no existe en Azure AD." }
            if ($grupodered -notlike 'POAZ_*') { throw "El grupo '$grupodered' no corresponde a un grupo 'POAZ' válido." }
            if ($grupodered -notlike 'POAZ_SOPORTE_*' -and $grupodered -notlike 'POAZ_OPERATOR_*' -and $grupodered -notlike 'POAZ_READER_*' -and $grupodered -notlike 'POAZ_NET_*') {
                throw "El grupo '$grupodered' no corresponde a un grupo 'POAZ' cross válido."
            }
            if ($grupodered -notlike '*_PROD') { throw "El grupo '$grupodered' no corresponde a un grupo 'POAZ PROD' cross válido." }
            if ($rolesRestringidos -contains $roleName) { throw "El Rol '$roleName' no está permitido solicitarlo por este medio." }
            $idgrupodered = $group.id
            $assignments = Get-AzRoleAssignment -ObjectId $idgrupodered -Scope $scopePath
            $Assigned = $assignments | Where-Object { $_.RoleDefinitionName -eq $roleName }
            if ($Assigned) { Write-Host "El Grupo de Red '$idgrupodered' ya tiene el rol '$roleName' asignado a nivel de Management Group." }
        }
    }
    "Subscription" {
        $subscription = Get-AzSubscription -SubscriptionName $subscriptionName -ErrorAction SilentlyContinue
        if (-not $subscription) { throw "Suscripción '$subscriptionName' no encontrada" }
        if ($ambiente -ne "Producción") { throw "El ambiente debe ser productivo para este tipo de solicitud." }

        if ($principalType -eq "Service Principal") {
            $sp = Get-AzADServicePrincipal -DisplayName $principalName -ErrorAction SilentlyContinue
            if (-not $sp) { throw "El Service Principal '$principalName' no existe en Azure AD." }
            if ($principalName -notmatch "PRO") {
                throw "El Service Principal '$principalName' no es de producción. Favor de ingresar correctamente el Service Principal."
            }
            if ($subscriptionName -notlike "*$codapp*") {
                throw "El código de aplicación '$codapp' no corresponde a la suscripción '$subscriptionName'."
            }
            $IdSuscripcion = $subscription.Id
            if (-not $IdSuscripcion) { throw "La suscripción no existe." }
            Set-AzContext -Subscription $IdSuscripcion -Force
            if ($rolesRestringidos -contains $roleName) {
                throw "El Rol '$roleName' no está permitido solicitarlo por este medio, se procede a cancelar la solicitud"
            }
            $role = Get-AzRoleDefinition | Where-Object {$_.Name -eq $roleName}
            if (-not $role) { throw "El rol '$roleName' NO está disponible para la suscripción '$subscriptionName'." }
            $idsp = $sp.Id
            $assignments = Get-AzRoleAssignment -ObjectId $idsp -Scope "/subscriptions/$IdSuscripcion"
            $Assigned = $assignments | Where-Object { $_.RoleDefinitionName -eq $roleName }
            if ($Assigned) {
                Write-Host "El Service Principal '$principalName' ya tiene el rol '$roleName' asignado a nivel de suscripción."
            }
            if ($assignmentType -eq "Permanente") {
                Write-Host "Asignando rol permanente en la suscripción..."
                New-AzRoleAssignment -ObjectId $idsp -RoleDefinitionName $roleName -Scope "/subscriptions/$IdSuscripcion"
                Write-Host "Se agregó el rol '$roleName' permanente correspondiente al Service Principal '$principalName' en la suscripción '$subscriptionName'"
            }
            elseif ($assignmentType -eq "Temporal") {
                $horaPeruTextoini = $startTime
                $horaPeruTextofin = $endTime
                $horaUTCini = [datetime]::ParseExact($horaPeruTextoini, "yyyy-MM-dd HH:mm", $null)
                $horaUTCini2 = [datetime]::SpecifyKind($horaUTCini, [System.DateTimeKind]::Utc)
                $horaUTCfin = [datetime]::ParseExact($horaPeruTextofin, "yyyy-MM-dd HH:mm", $null)
                $horaUTCfin2 = [datetime]::SpecifyKind($horaUTCfin, [System.DateTimeKind]::Utc)
                $zonaPeru = [System.TimeZoneInfo]::FindSystemTimeZoneById("SA Pacific Standard Time")
                $horaPeruini = [System.TimeZoneInfo]::ConvertTimeFromUtc($horaUTCini, $zonaPeru)
                $horaPerufin = [System.TimeZoneInfo]::ConvertTimeFromUtc($horaUTCfin, $zonaPeru)
                $guid = [guid]::NewGuid().ToString()
                $startTimeISO = Get-Date $horaUTCini2 -Format o
                $endTimeISO = Get-Date $horaUTCfin2 -Format o
                $rolId = (Get-AzRoleDefinition -Name $roleName).Id
                $Justification = "Asignación de rol temporal por medio de GitHub Actions"

                New-AzRoleAssignmentScheduleRequest -Name $guid `
                    -Scope "/subscriptions/$IdSuscripcion" `
                    -ExpirationType AfterDateTime `
                    -PrincipalId $idsp `
                    -RequestType AdminAssign `
                    -RoleDefinitionId "/providers/Microsoft.Authorization/roleDefinitions/$rolId" `
                    -ScheduleInfoStartDateTime $startTimeISO `
                    -ExpirationEndDateTime $endTimeISO `
                    -Justification $Justification

                Write-Host "Se agregó el rol '$roleName' temporal correspondiente al Service Principal '$principalName' en la suscripción '$subscriptionName' (Vigencia: $($horaPeruini.ToString('dd/MM/yyyy HH:mm')) hasta $($horaPerufin.ToString('dd/MM/yyyy HH:mm')) )"
            }
        }
        else {
            $scopePath = "/subscriptions/$($subscription.Id)"
            $noPermitidas = @("DTI - INF - INFR - Servicios Compartidos", "Azure EA - Credicorp")
            if ($noPermitidas -contains $subscriptionName) { throw "No está permitida la asignación de roles para la suscripción '$subscriptionName'." }
            $group = Get-AzADGroup -DisplayName $grupodered -ErrorAction SilentlyContinue
            if (-not $group) { throw "El grupo de red '$grupodered' no existe en Azure AD." }
            $costGroup = "POAZ_COSTMANAGEMENT_$codapp"
            $dashGroup = "POAZ_DASHBOARD_$codapp"
            if ($roleName -ne "Cost Management Reader" -and $roleName -ne "Dashboard Reader") { throw "Rol no válido: '$roleName'." }
            if ($grupodered -ne $costGroup -and $grupodered -ne $dashGroup) { throw "Grupo de red no válido: '$grupodered'." }
            if ($grupodered -eq $costGroup -and $roleName -ne "Cost Management Reader") { throw "El grupo '$grupodered' requiere el rol 'Cost Management Reader'." }
            if ($grupodered -eq $dashGroup -and $roleName -ne "Dashboard Reader") { throw "El grupo '$grupodered' requiere el rol 'Dashboard Reader'." }
            if ($rolesRestringidos -contains $roleName) { throw "El Rol '$roleName' no está permitido solicitarlo por este medio." }
            $role = Get-AzRoleDefinition | Where-Object {$_.Name -eq $roleName}
            if (-not $role) { throw "El rol '$roleName' NO está disponible para la suscripción '$subscriptionName'." }
            $idgrupodered = $group.id
            $assignments = Get-AzRoleAssignment -ObjectId $idgrupodered -Scope $scopePath
            $Assigned = $assignments | Where-Object { $_.RoleDefinitionName -eq $roleName }
            if ($Assigned) { Write-Host "El grupo '$grupodered' ya tiene el rol '$roleName' asignado a nivel de suscripción." }
        }
    }
    "Resource Group" {
        $subscription = Get-AzSubscription -SubscriptionName $subscriptionName -ErrorAction SilentlyContinue
        if (-not $subscription) { throw "Suscripción '$subscriptionName' no encontrada" }
        $scopePath = "/subscriptions/$($subscription.Id)/resourceGroups/$resourceGroupName"

        if ($principalType -eq "Service Principal") {
            if (-not $resourceGroupName) { throw "No se encontró el Nombre del Grupo de Recursos." }

            if ($resourceGroupName -like "*$codapp*") {
                Write-Host "El código de aplicación '$codapp' corresponde al grupo de recursos '$resourceGroupName'."
            } else {
                throw "El código de aplicación '$codapp' no corresponde al grupo de recursos '$resourceGroupName'."
            }

            $IdSuscripcion = $subscription.Id
            if (-not $IdSuscripcion) { throw "La suscripción no existe." }
            Set-AzContext -Subscription $IdSuscripcion -Force

            $resourceGroup = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue
            if ($null -eq $resourceGroup) { throw  "El grupo de recursos '$resourceGroupName' NO existe." }

            if (-not $resourceGroup.Tags.ContainsKey("environment")) {
                throw "El grupo de recursos '$resourceGroupName' no cuenta con un ambiente definido."
            }

            $tagValue = $resourceGroup.Tags["environment"].ToLower()
            switch ($tagValue) {
                "prod" { $ambienteEsperado = "Producción" }
                "desa" { $ambienteEsperado = "Desarrollo" }
                "cert" { $ambienteEsperado = "Certificación" }
                default { throw "El grupo de recursos '$resourceGroupName' no cuenta con un ambiente definido." }
            }
            if ($ambienteEsperado -ne $ambiente) {
                throw "El grupo de recursos '$resourceGroupName' no corresponde al ambiente seleccionado '$ambiente'."
            }

            switch ($ambiente.ToUpper()) {
                "DESARROLLO" {
                    if ($principalName -notmatch "des") {
                        throw "El Service Principal '$principalName' no corresponde al ambiente 'Desarrollo'."
                    }
                }
                "CERTIFICACIÓN" {
                    if ($principalName -notmatch "cer") {
                        throw "El Service Principal '$principalName' no corresponde al ambiente 'Certificación'."
                    }
                }
                "PRODUCCIÓN" {
                    if ($principalName -notmatch "pro") {
                        throw "El Service Principal '$principalName' no corresponde al ambiente 'Producción'."
                    }
                }
                Default {
                    throw "Ambiente '$ambiente' no reconocido. Usa Desarrollo, Certificación o Producción."
                }
            }

            $sp = Get-AzADServicePrincipal -DisplayName $principalName -ErrorAction SilentlyContinue
            if (-not $sp) { throw "El Service Principal '$principalName' no existe en Azure AD." }
            $idsp = $sp.Id

            if ($rolesRestringidos -contains $roleName) {
                throw "El Rol '$roleName' no está permitido solicitarlo por este medio, se procede a cancelar la solicitud"
            }

            $role = Get-AzRoleDefinition | Where-Object {$_.Name -eq $roleName}
            if (-not $role) { throw "El rol '$roleName' NO está disponible para la suscripción '$subscriptionName'." }

            $asignacion = Get-AzRoleAssignment -ObjectId $idsp -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue | Where-Object { $_.RoleDefinitionName -eq $roleName }
            if ($null -ne $asignacion) {
                Write-Host "El rol '$roleName' ya está asignado al Service Principal '$principalName' en el Resource Group '$resourceGroupName'."
            }

            if ($assignmentType -eq "Permanente") {
                Write-Host "Asignando rol permanente en el Resource Group..."
                New-AzRoleAssignment -ObjectId $idsp -RoleDefinitionName $roleName -ResourceGroupName $resourceGroupName
                Write-Host "Se agregó el rol '$roleName' permanente correspondiente al Service Principal '$principalName' en el grupo de recursos '$resourceGroupName'"
            }
            elseif ($assignmentType -eq "Temporal") {
                $horaPeruTextoini = $startTime
                $horaPeruTextofin = $endTime
                $horaUTCini = [datetime]::ParseExact($horaPeruTextoini, "yyyy-MM-dd HH:mm", $null)
                $horaUTCini2 = [datetime]::SpecifyKind($horaUTCini, [System.DateTimeKind]::Utc)
                $horaUTCfin = [datetime]::ParseExact($horaPeruTextofin, "yyyy-MM-dd HH:mm", $null)
                $horaUTCfin2 = [datetime]::SpecifyKind($horaUTCfin, [System.DateTimeKind]::Utc)
                $zonaPeru = [System.TimeZoneInfo]::FindSystemTimeZoneById("SA Pacific Standard Time")
                $horaPeruini = [System.TimeZoneInfo]::ConvertTimeFromUtc($horaUTCini, $zonaPeru)
                $horaPerufin = [System.TimeZoneInfo]::ConvertTimeFromUtc($horaUTCfin, $zonaPeru)
                $guid = [guid]::NewGuid().ToString()
                $startTimeISO = Get-Date $horaUTCini2 -Format o
                $endTimeISO = Get-Date $horaUTCfin2 -Format o
                $rolId = (Get-AzRoleDefinition -Name $roleName).Id
                $Justification = "Asignación de rol temporal por medio de GitHub Actions"

                New-AzRoleAssignmentScheduleRequest -Name $guid `
                    -Scope "/subscriptions/$IdSuscripcion/resourceGroups/$resourceGroupName" `
                    -ExpirationType AfterDateTime `
                    -PrincipalId $idsp `
                    -RequestType AdminAssign `
                    -RoleDefinitionId "/providers/Microsoft.Authorization/roleDefinitions/$rolId" `
                    -ScheduleInfoStartDateTime $startTimeISO `
                    -ExpirationEndDateTime $endTimeISO `
                    -Justification $Justification

                Write-Host "Se agregó el rol '$roleName' temporal correspondiente al Service Principal '$principalName' en el grupo de recursos '$resourceGroupName' (Vigencia: $($horaPeruini.ToString('dd/MM/yyyy HH:mm')) hasta $($horaPerufin.ToString('dd/MM/yyyy HH:mm')) )"
            }
        }
        else {
            $resourceGroup = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue
            if ($null -eq $resourceGroup) { throw  "El grupo de recursos '$resourceGroupName' NO existe." }
            if (-not $resourceGroup.Tags.ContainsKey("environment")) { throw "El grupo de recursos '$resourceGroupName' no cuenta con un ambiente definido." }
            $tagValue = $resourceGroup.Tags["environment"].ToLower()
            switch ($tagValue) {
                "prod" { $ambienteEsperado = "Producción" }
                "desa" { $ambienteEsperado = "Desarrollo" }
                "cert" { $ambienteEsperado = "Certificación" }
                default { throw "El grupo de recursos '$resourceGroupName' no cuenta con un ambiente definido." }
            }
            if ($ambienteEsperado -ne $ambiente) { throw "El grupo de recursos '$resourceGroupName' no corresponde al ambiente seleccionado '$ambiente'." }
            $group = Get-AzADGroup -DisplayName $grupodered -ErrorAction SilentlyContinue
            if (-not $group) { throw "El grupo de red '$grupodered' no existe en Azure AD." }
            if ($rolesRestringidos -contains $roleName) { throw "El Rol '$roleName' no está permitido solicitarlo por este medio." }
            $idgrupodered = $group.id
            $asignacion = Get-AzRoleAssignment -ObjectId $idgrupodered -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue | Where-Object { $_.RoleDefinitionName -eq $roleName}
            if ($null -ne $asignacion) { Write-Host "El rol '$roleName' ya está asignado al grupo de red '$grupodered' en el Resource Group '$resourceGroupName'." }
        }
    }
    "Resource" {
        $subscription = Get-AzSubscription -SubscriptionName $subscriptionName -ErrorAction SilentlyContinue
        if (-not $subscription) { throw "Suscripción '$subscriptionName' no encontrada" }
        if (-not $resourceGroupName) { throw "No se encontró el Nombre del Grupo de Recursos." }
        if (-not $resourceName) { throw "No se encontró el Nombre del Recurso." }
        $scopePath = "/subscriptions/$($subscription.Id)/resourceGroups/$resourceGroupName/providers/$resourceType/$resourceName"

        if ($principalType -eq "Service Principal") {
            if ($resourceGroupName -like "*$codapp*") {
                Write-Host "El código de aplicación '$codapp' corresponde al grupo de recursos '$resourceGroupName'."
            } else {
                throw "El código de aplicación '$codapp' no corresponde al grupo de recursos '$resourceGroupName'."
            }

            $IdSuscripcion = $subscription.Id
            if (-not $IdSuscripcion) { throw "La suscripción no existe." }
            Set-AzContext -Subscription $IdSuscripcion -Force

            $resourceGroup = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue
            if ($null -eq $resourceGroup) { throw  "El grupo de recursos '$resourceGroupName' NO existe." }

            if (-not $resourceGroup.Tags.ContainsKey("environment")) {
                throw "El recurso '$resourceName' no cuenta con un ambiente definido."
            }

            $tagValue = $resourceGroup.Tags["environment"].ToLower()
            switch ($tagValue) {
                "prod" { $ambienteEsperado = "Producción" }
                "desa" { $ambienteEsperado = "Desarrollo" }
                "cert" { $ambienteEsperado = "Certificación" }
                default { throw "El recurso '$resourceName' no cuenta con un ambiente definido." }
            }
            if ($ambienteEsperado -ne $ambiente) {
                throw "El grupo de recursos '$resourceGroupName' no corresponde al ambiente seleccionado '$ambiente'."
            }

            switch ($ambiente.ToUpper()) {
                "DESARROLLO" {
                    if ($principalName -notmatch "des") {
                        throw "El Service Principal '$principalName' no corresponde al ambiente 'Desarrollo'."
                    }
                }
                "CERTIFICACIÓN" {
                    if ($principalName -notmatch "cer") {
                        throw "El Service Principal '$principalName' no corresponde al ambiente 'Certificación'."
                    }
                }
                "PRODUCCIÓN" {
                    if ($principalName -notmatch "pro") {
                        throw "El Service Principal '$principalName' no corresponde al ambiente 'Producción'."
                    }
                }
                Default {
                    throw "Ambiente '$ambiente' no reconocido. Usa Desarrollo, Certificación o Producción."
                }
            }

            $sp = Get-AzADServicePrincipal -DisplayName $principalName -ErrorAction SilentlyContinue
            if (-not $sp) { throw "El Service Principal '$principalName' no existe en Azure AD." }
            $idsp = $sp.Id

            if ($rolesRestringidos -contains $roleName) {
                throw "El Rol '$roleName' no está permitido solicitarlo por este medio, se procede a cancelar la solicitud"
            }

            $role = Get-AzRoleDefinition | Where-Object {$_.Name -eq $roleName}
            if (-not $role) { throw "El rol '$roleName' NO está disponible para la suscripción '$subscriptionName'." }

            $resource = Get-AzResource -Name $resourceName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
            if(-not $resource){ throw "El recurso '$resourceName' no existe en el grupo de recursos '$resourceGroupName'." }
            $idrecurso = $resource.ResourceId

            $asignacion = Get-AzRoleAssignment -Scope $idrecurso -ObjectId $idsp -ErrorAction SilentlyContinue | Where-Object { $_.RoleDefinitionName -eq $roleName }
            if ($null -ne $asignacion) {
                Write-Host "Ya existe una asignación del rol '$roleName' para el Service Principal '$principalName'."
            }

            if ($assignmentType -eq "Permanente") {
                Write-Host "Asignando rol permanente en el recurso..."
                New-AzRoleAssignment -ObjectId $idsp -RoleDefinitionName $roleName -ResourceGroupName $resourceGroupName -ResourceName $resourceName -ResourceType $resourceType
                Write-Host "Se agregó el rol '$roleName' permanente correspondiente al Service Principal '$principalName' en el recurso '$resourceName'"
            }
            elseif ($assignmentType -eq "Temporal") {
                $horaPeruTextoini = $startTime
                $horaPeruTextofin = $endTime
                $horaUTCini = [datetime]::ParseExact($horaPeruTextoini, "yyyy-MM-dd HH:mm", $null)
                $horaUTCini2 = [datetime]::SpecifyKind($horaUTCini, [System.DateTimeKind]::Utc)
                $horaUTCfin = [datetime]::ParseExact($horaPeruTextofin, "yyyy-MM-dd HH:mm", $null)
                $horaUTCfin2 = [datetime]::SpecifyKind($horaUTCfin, [System.DateTimeKind]::Utc)
                $zonaPeru = [System.TimeZoneInfo]::FindSystemTimeZoneById("SA Pacific Standard Time")
                $horaPeruini = [System.TimeZoneInfo]::ConvertTimeFromUtc($horaUTCini, $zonaPeru)
                $horaPerufin = [System.TimeZoneInfo]::ConvertTimeFromUtc($horaUTCfin, $zonaPeru)
                $guid = [guid]::NewGuid().ToString()
                $startTimeISO = Get-Date $horaUTCini2 -Format o
                $endTimeISO = Get-Date $horaUTCfin2 -Format o
                $rolId = (Get-AzRoleDefinition -Name $roleName).Id
                $Justification = "Asignación de rol temporal por medio de GitHub Actions"

                New-AzRoleAssignmentScheduleRequest -Name $guid `
                    -Scope $idrecurso `
                    -ExpirationType AfterDateTime `
                    -PrincipalId $idsp `
                    -RequestType AdminAssign `
                    -RoleDefinitionId "/providers/Microsoft.Authorization/roleDefinitions/$rolId" `
                    -ScheduleInfoStartDateTime $startTimeISO `
                    -ExpirationEndDateTime $endTimeISO `
                    -Justification $Justification

                Write-Host "Se agregó el rol '$roleName' temporal correspondiente al Service Principal '$principalName' en el recurso '$resourceName' (Vigencia: $($horaPeruini.ToString('dd/MM/yyyy HH:mm')) hasta $($horaPerufin.ToString('dd/MM/yyyy HH:mm')) )"
            }
        }
        else {
            $resourceGroup = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue
            if ($null -eq $resourceGroup) { throw  "El grupo de recursos '$resourceGroupName' NO existe." }
            $group = Get-AzADGroup -DisplayName $grupodered -ErrorAction SilentlyContinue
            if (-not $group) { throw "El grupo de red '$grupodered' no existe en Azure AD." }
            $resource = Get-AzResource -Name $resourceName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
            if(-not $resource){ throw "El recurso '$resourceName' no existe en el grupo de recursos '$resourceGroupName'." }
            if ($rolesRestringidos -contains $roleName) { throw "El Rol '$roleName' no está permitido solicitarlo por este medio." }
            $role = Get-AzRoleDefinition | Where-Object {$_.Name -eq $roleName}
            if (-not $role) { throw "El rol '$roleName' NO está disponible para la suscripción '$subscriptionName'." }
            $idgrupodered = $group.id
            $asignacion = Get-AzRoleAssignment -Scope $resource.ResourceId -ObjectId $idgrupodered -ErrorAction SilentlyContinue | Where-Object { $_.RoleDefinitionName -eq $roleName }
            if ($null -ne $asignacion) { Write-Host "Ya existe una asignación del rol '$roleName' para el grupo de red '$grupodered'." }
        }
    }
    default { throw "ScopeType '$scopeType' no soportado." }
}

# Obtener el principal ID
$principalId = $null
switch ($principalType) {
    "Security Group" {
        $group = Get-AzADGroup -DisplayName $principalName -ErrorAction SilentlyContinue
        if ($group) { $principalId = $group.Id }
    }
    "Service Principal" {
        $sp = Get-AzADServicePrincipal -DisplayName $principalName -ErrorAction SilentlyContinue
        if ($sp) { $principalId = $sp.Id }
    }
    "Managed Identity" {
        $mi = Get-AzADServicePrincipal -DisplayName $principalName -ErrorAction SilentlyContinue
        if ($mi) { $principalId = $mi.Id }
    }
    "User" {
        $user = Get-AzADUser -DisplayName $principalName -ErrorAction SilentlyContinue
        if (-not $user) {
            $user = Get-AzADUser -UserPrincipalName $principalName -ErrorAction SilentlyContinue
        }
        if ($user) { $principalId = $user.Id }
    }
}
if (-not $principalId) { throw "No se encontró el principal '$principalName' del tipo '$principalType'" }

Write-Host "`n=== RESUMEN DE ASIGNACIÓN ===" -ForegroundColor Magenta
Write-Host "Principal: $principalName ($principalType)" -ForegroundColor White
Write-Host "Rol: $roleName" -ForegroundColor White
Write-Host "Ámbito: $scopeType" -ForegroundColor White
Write-Host "Scope Path: $scopePath" -ForegroundColor White
Write-Host "Tipo: $assignmentType" -ForegroundColor White

if ($assignmentType -eq "Temporal") {
    Write-Host "Inicio: $startTime" -ForegroundColor White
    Write-Host "Fin: $endTime" -ForegroundColor White
    Write-Warning "Las asignaciones temporales requieren PIM. Se creará una asignación permanente."
}

Write-Host "`nEjecutando asignación de rol..." -ForegroundColor Yellow

try {
    $params = @{
        ObjectId = $principalId
        RoleDefinitionName = $roleName
        Scope = $scopePath
    }
    $assignment = New-AzRoleAssignment @params
    Write-Host "`n✅ Asignación de rol completada exitosamente!" -ForegroundColor Green
    Write-Host "Assignment ID: $($assignment.RoleAssignmentId)" -ForegroundColor Cyan
} catch {
    Write-Error "Error al crear la asignación: $($_.Exception.Message)"
}