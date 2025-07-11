<#
.SYNOPSIS
    Script unificado para asignación de roles en Azure, soportando Service Principal y Security Group.
    Orientado a ejecución automatizada (GitHub Actions, pipelines, etc).
    Todos los datos se pasan por parámetros.
#>

param(
    [Parameter(Mandatory=$true)][string]$principalType,        # "Service Principal" o "Security Group"
    [Parameter(Mandatory=$true)][string]$principalName,
    [Parameter(Mandatory=$true)][string]$scopeType,            # "Management Group", "Subscription", "Resource Group", "Resource"
    [string]$managementGroup,
    [string]$subscriptionName,
    [string]$resourceGroupName,
    [string]$resourceType,
    [string]$resourceName,
    [Parameter(Mandatory=$true)][string]$roleName,
    [string]$codapp,
    [string]$grupodered,
    [Parameter(Mandatory=$true)][string]$ambiente,             # "Desarrollo", "Certificación", "Producción"
    [string]$assignmentType,                                   # "Permanente" o "Temporal"
    [string]$startTime,
    [string]$endTime
)

$ErrorActionPreference = "Stop"

$rolesRestringidos = @(
   "Owner","Contributor","User Access Administrator","Reservations Administrator",
   "Access Review Operator Service Role","Role Based Access Control Administrator",
   "Service Group Contributor","Administrador IBM Cloud","Environment Automation",
   "Environment Automation II","Rol Administrador de Accesos","Rol Administrador de Accesos PIM",
   "Administrador Modelo Soporte","Environment Operator APIM","Rol Modificar NSG SOAR",
   "Rol Networking Whitelist - Ambientes Previos","Developer Environment Operator",
   "Environment Operator","Reader Environment Certi","Reader Certi QA"
)

# 1. Conexión a Azure
try {
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "No estás conectado a Azure. Ejecutando Connect-AzAccount..." -ForegroundColor Yellow
        Connect-AzAccount
    }
    Write-Host "Conectado a Azure - Tenant: $($context.Tenant.Id)" -ForegroundColor Green
} catch {
    Write-Error "Error al conectar con Azure: $($_.Exception.Message)"
    exit 1
}

# 2. Determinar scopePath
switch ($scopeType) {
    "Management Group" {
        if (-not $managementGroup) { throw "Debe especificar el nombre del Management Group." }
        $scopePath = "/providers/Microsoft.Management/managementGroups/$managementGroup"
    }
    "Subscription" {
        if (-not $subscriptionName) { throw "Debe especificar el nombre de la suscripción." }
        $subscription = Get-AzSubscription -SubscriptionName $subscriptionName -ErrorAction Stop
        $scopePath = "/subscriptions/$($subscription.Id)"
    }
    "Resource Group" {
        if (-not $subscriptionName -or -not $resourceGroupName) { throw "Debe especificar la suscripción y el resource group." }
        $subscription = Get-AzSubscription -SubscriptionName $subscriptionName -ErrorAction Stop
        $scopePath = "/subscriptions/$($subscription.Id)/resourceGroups/$resourceGroupName"
    }
    "Resource" {
        if (-not $subscriptionName -or -not $resourceGroupName -or -not $resourceType -or -not $resourceName) {
            throw "Debe especificar suscripción, resource group, tipo y nombre de recurso."
        }
        $subscription = Get-AzSubscription -SubscriptionName $subscriptionName -ErrorAction Stop
        $scopePath = "/subscriptions/$($subscription.Id)/resourceGroups/$resourceGroupName/providers/$resourceType/$resourceName"
    }
    default { throw "ScopeType '$scopeType' no soportado." }
}

# 3. Lógica y validaciones completas según tipo de principal y scope
function ValidarAmbienteRG {
    param($rg, $ambiente)
    if (-not $rg.Tags.ContainsKey("environment")) { throw "El RG no tiene tag 'environment'." }
    $tagValue = $rg.Tags["environment"].ToLower()
    $ambienteEsperado = switch ($tagValue) { "prod" {"Producción"} "desa" {"Desarrollo"} "cert" {"Certificación"} default {throw "Tag 'environment' inválido."} }
    if ($ambienteEsperado -ne $ambiente) { throw "El RG no corresponde al ambiente '$ambiente'." }
}

if ($principalType -eq "Service Principal") {
    # --- Lógica para Service Principal (automatizada, completa) ---
    $sp = Get-AzADServicePrincipal -DisplayName $principalName -ErrorAction SilentlyContinue
    if (-not $sp) { throw "No se encontró el Service Principal '$principalName'." }
    $principalId = $sp.Id

    switch ($scopeType) {
        "Management Group" {
            if ($ambiente -ne "Producción") { throw "El ambiente debe ser 'Producción' para Management Group." }
            if ($rolesRestringidos -contains $roleName) { throw "El Rol '$roleName' no está permitido." }
            $assignments = Get-AzRoleAssignment -ObjectId $principalId -Scope $scopePath -ErrorAction SilentlyContinue
            if ($assignments | Where-Object { $_.RoleDefinitionName -eq $roleName }) {
                Write-Host "El Service Principal ya tiene el rol asignado en el Management Group."
                exit 0
            }
        }
        "Subscription" {
            if ($ambiente -ne "Producción") { throw "El ambiente debe ser 'Producción' para Subscription." }
            if ($codapp -and $subscriptionName -notlike "*$codapp*") {
                throw "El código de aplicación '$codapp' no corresponde a la suscripción '$subscriptionName'."
            }
            $noPermitidas = @("DTI - INF - INFR - Servicios Compartidos", "Azure EA - Credicorp")
            if ($noPermitidas -contains $subscriptionName) {
                throw "No está permitida la asignación de roles para la suscripción '$subscriptionName'."
            }
            if ($rolesRestringidos -contains $roleName) { throw "El Rol '$roleName' no está permitido." }
            $role = Get-AzRoleDefinition | Where-Object {$_.Name -eq $roleName}
            if (-not $role) { throw "El rol '$roleName' NO está disponible para la suscripción '$subscriptionName'." }
            $assignments = Get-AzRoleAssignment -ObjectId $principalId -Scope $scopePath -ErrorAction SilentlyContinue
            if ($assignments | Where-Object { $_.RoleDefinitionName -eq $roleName }) {
                Write-Host "El Service Principal ya tiene el rol asignado en la suscripción."
                exit 0
            }
        }
        "Resource Group" {
            $rg = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue
            if (-not $rg) { throw "El Resource Group '$resourceGroupName' no existe." }
            ValidarAmbienteRG $rg $ambiente
            if ($codapp -and $resourceGroupName -notlike "*$codapp*") {
                throw "El código de aplicación '$codapp' no corresponde al RG '$resourceGroupName'."
            }
            if ($rolesRestringidos -contains $roleName) { throw "El Rol '$roleName' no está permitido." }
            $role = Get-AzRoleDefinition | Where-Object {$_.Name -eq $roleName}
            if (-not $role) { throw "El rol '$roleName' NO está disponible para la suscripción '$subscriptionName'." }
            $assignments = Get-AzRoleAssignment -ObjectId $principalId -Scope $scopePath -ErrorAction SilentlyContinue
            if ($assignments | Where-Object { $_.RoleDefinitionName -eq $roleName }) {
                Write-Host "El Service Principal ya tiene el rol asignado en el RG."
                exit 0
            }
        }
        "Resource" {
            $rg = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue
            if (-not $rg) { throw "El Resource Group '$resourceGroupName' no existe." }
            ValidarAmbienteRG $rg $ambiente
            if ($codapp -and $resourceGroupName -notlike "*$codapp*") {
                throw "El código de aplicación '$codapp' no corresponde al RG '$resourceGroupName'."
            }
            $resource = Get-AzResource -Name $resourceName -ResourceGroupName $resourceGroupName -ResourceType $resourceType -ErrorAction SilentlyContinue
            if (-not $resource) { throw "El recurso '$resourceName' no existe en el RG '$resourceGroupName'." }
            if ($rolesRestringidos -contains $roleName) { throw "El Rol '$roleName' no está permitido." }
            $role = Get-AzRoleDefinition | Where-Object {$_.Name -eq $roleName}
            if (-not $role) { throw "El rol '$roleName' NO está disponible para la suscripción '$subscriptionName'." }
            $assignments = Get-AzRoleAssignment -ObjectId $principalId -Scope $scopePath -ErrorAction SilentlyContinue
            if ($assignments | Where-Object { $_.RoleDefinitionName -eq $roleName }) {
                Write-Host "El Service Principal ya tiene el rol asignado en el recurso."
                exit 0
            }
        }
    }
}
elseif ($principalType -eq "Security Group") {
    # --- Lógica para Grupo de Red (automatizada, completa) ---
    $group = Get-AzADGroup -DisplayName $principalName -ErrorAction SilentlyContinue
    if (-not $group) { throw "El grupo de red '$principalName' no existe en Azure AD." }
    $principalId = $group.Id

    switch ($scopeType) {
        "Management Group" {
            if ($ambiente -ne "Producción") { throw "El ambiente debe ser 'Producción' para Management Group." }
            if ($principalName -notlike 'POAZ_*') { throw "El grupo '$principalName' no corresponde a un grupo 'POAZ' válido." }
            if ($principalName -notlike '*_PROD') { throw "El grupo '$principalName' no corresponde a un grupo 'POAZ PROD' válido." }
            if ($rolesRestringidos -contains $roleName) { throw "El Rol '$roleName' no está permitido." }
            $assignments = Get-AzRoleAssignment -ObjectId $principalId -Scope $scopePath -ErrorAction SilentlyContinue
            if ($assignments | Where-Object { $_.RoleDefinitionName -eq $roleName }) {
                Write-Host "El grupo de red ya tiene el rol asignado en el Management Group."
                exit 0
            }
        }
        "Subscription" {
            if ($ambiente -ne "Producción") { throw "El ambiente debe ser 'Producción' para Subscription." }
            $costGroup = "POAZ_COSTMANAGEMENT_$codapp"
            $dashGroup = "POAZ_DASHBOARD_$codapp"
            if ($roleName -ne "Cost Management Reader" -and $roleName -ne "Dashboard Reader") {
                throw "Rol no válido: '$roleName'. Solo se permiten 'Cost Management Reader' o 'Dashboard Reader'."
            }
            if ($principalName -ne $costGroup -and $principalName -ne $dashGroup) {
                throw "Grupo de red no válido: '$principalName'. Debe ser '$costGroup' o '$dashGroup'."
            }
            if ($principalName -eq $costGroup -and $roleName -ne "Cost Management Reader") {
                throw "El grupo '$principalName' requiere el rol 'Cost Management Reader'."
            }
            if ($principalName -eq $dashGroup -and $roleName -ne "Dashboard Reader") {
                throw "El grupo '$principalName' requiere el rol 'Dashboard Reader'."
            }
            if ($rolesRestringidos -contains $roleName) { throw "El Rol '$roleName' no está permitido." }
            $role = Get-AzRoleDefinition | Where-Object {$_.Name -eq $roleName}
            if (-not $role) { throw "El rol '$roleName' NO está disponible para la suscripción '$subscriptionName'." }
            $assignments = Get-AzRoleAssignment -ObjectId $principalId -Scope $scopePath -ErrorAction SilentlyContinue
            if ($assignments | Where-Object { $_.RoleDefinitionName -eq $roleName }) {
                Write-Host "El grupo de red ya tiene el rol asignado en la suscripción."
                exit 0
            }
        }
        "Resource Group" {
            $rg = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue
            if (-not $rg) { throw "El Resource Group '$resourceGroupName' no existe." }
            ValidarAmbienteRG $rg $ambiente
            if ($principalName -notmatch "POAZ") { throw "El grupo '$principalName' no contiene 'POAZ' en su nombre." }
            if ($codapp -and $principalName -notmatch $codapp) { throw "El grupo '$principalName' no corresponde al '$codapp'." }
            $grupoDev = "POAZ_DEV_${codapp}_DESA"
            $grupoLTDev  = "POAZ_LT_${codapp}_DESA"
            $grupoLTcert = "POAZ_LT_${codapp}_CERT"
            $grupoQAcert = "POAZ_QA_${codapp}_CERT"
            $roldev = "Developer Environment Operator"
            $roldevlt = "Environment Operator"
            $rolcertlt = "Reader Environment Certi"
            $rolcertqa = "Reader Certi QA"
            if (($roleName -eq $roldev -or $roleName -eq $roldevlt) -and $ambiente -ne "Desarrollo") {
                throw "El rol '$roleName' solo es válido para ambiente 'Desarrollo'."
            }
            if (($roleName -eq $rolcertlt -or $roleName -eq $rolcertqa) -and $ambiente -ne "Certificación") {
                throw "El rol '$roleName' solo es válido para ambiente 'Certificación'."
            }
            if ($rolesRestringidos -contains $roleName) { throw "El Rol '$roleName' no está permitido." }
            $role = Get-AzRoleDefinition | Where-Object {$_.Name -eq $roleName}
            if (-not $role) { throw "El rol '$roleName' NO está disponible para la suscripción '$subscriptionName'." }
            $assignments = Get-AzRoleAssignment -ObjectId $principalId -Scope $scopePath -ErrorAction SilentlyContinue
            if ($assignments | Where-Object { $_.RoleDefinitionName -eq $roleName }) {
                Write-Host "El grupo de red ya tiene el rol asignado en el RG."
                exit 0
            }
        }
        "Resource" {
            $rg = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue
            if (-not $rg) { throw "El Resource Group '$resourceGroupName' no existe." }
            ValidarAmbienteRG $rg $ambiente
            $resource = Get-AzResource -Name $resourceName -ResourceGroupName $resourceGroupName -ResourceType $resourceType -ErrorAction SilentlyContinue
            if (-not $resource) { throw "El recurso '$resourceName' no existe en el RG '$resourceGroupName'." }
            if ($codapp -and $principalName -notmatch $codapp) { throw "El grupo '$principalName' no corresponde al '$codapp'." }
            $grRestringidos = @("POAZ_DEV_${codapp}_DESA","POAZ_LT_${codapp}_DESA","POAZ_LT_${codapp}_CERT","POAZ_QA_${codapp}_CERT")
            if ($grRestringidos -contains $principalName) { throw "El grupo de red '$principalName' no está permitido para este tipo de solicitud" }
            if ($principalName -notlike '*_prod_poaz' -and $principalName -notlike '*_cert_poaz' -and $principalName -notlike '*_desa_poaz') {
                throw "El grupo '$principalName' no es un grupo 'POAZ' adicional de aplicación."
            }
            if ($principalName -like '*_prod_poaz' -and $ambiente -ne 'Producción') { throw "El grupo es productivo, pero el ambiente no es 'producción'." }
            if ($principalName -like '*_cert_poaz' -and $ambiente -ne 'Certificación') { throw "El grupo es de certificación, pero el ambiente no es 'certificación'." }
            if ($principalName -like '*_desa_poaz' -and $ambiente -ne 'Desarrollo') { throw "El grupo es de desarrollo, pero el ambiente no es 'desarrollo'." }
            if ($rolesRestringidos -contains $roleName) { throw "El Rol '$roleName' no está permitido." }
            $role = Get-AzRoleDefinition | Where-Object {$_.Name -eq $roleName}
            if (-not $role) { throw "El rol '$roleName' NO está disponible para la suscripción '$subscriptionName'." }
            $assignments = Get-AzRoleAssignment -ObjectId $principalId -Scope $scopePath -ErrorAction SilentlyContinue
            if ($assignments | Where-Object { $_.RoleDefinitionName -eq $roleName }) {
                Write-Host "El grupo de red ya tiene el rol asignado en el recurso."
                exit 0
            }
        }
    }
}
else {
    throw "Tipo de principal '$principalType' no soportado. Use 'Service Principal' o 'Security Group'."
}

# 4. Asignación de rol
Write-Host "`nAsignando rol '$roleName' a principal '$principalName' ($principalType) en scope: $scopePath" -ForegroundColor Cyan
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
    exit 1
}