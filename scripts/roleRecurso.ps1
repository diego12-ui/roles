using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

$body = ""
$statusCode = [HttpStatusCode]::OK
$codapp= $Request.Body.codapp
$suscripcion = $Request.Body.suscription
$rg = $Request.Body.resourcegroup
$ambiente = $Request.Body.ambiente
$recurso = $Request.Body.recurso
try {
 if (-not $suscripcion) {
        throw "No se encontró el Nombre de la Suscripcion."
    }
  if (-not $rg) {
        throw "No se encontró el Nombre del Grupo de Recursos."
    }
    if (-not $recurso) {
        throw "No se encontró el Nombre del Recursos."
    }

Write-Host "Iniciando sesión en Azure con Managed Identity..."
    Connect-AzAccount -Identity

#$suscripcionescompartidas = @(
#    "DTI - INF - INFR - Servicios Compartidos",
#    "Azure EA - Credicorp"
#)

Write-Host "Validando codigo de aplicación"
if ($rg -like "*$codapp*") {
        Write-Host "El codigo de aplicación '$codapp' corresponde al grupo de recursos '$rg'."
}else{
         throw "El codigo de aplicación '$codapp' no corresponde al grupo de recursos '$rg'."
}

Write-Host "Validando que la suscripcion exista en Azure"
$IdSuscripcion = (Get-AzSubscription -SubscriptionName $suscripcion).id
if ( -not $IdSuscripcion){
throw "La suscripcion no existe."
}

Set-AzContext -Subscription $IdSuscripcion -Force

Write-Host "Validando que el RG exista en Azure"

# Intentar obtenerlo
$resourceGroupName2 = Get-AzResourceGroup -Name $rg -ErrorAction SilentlyContinue
# Validar si existe
if ($null -eq $resourceGroupName2) {
   throw  "El grupo de recursos '$rg' NO existe."
}

$resourceGroupName = Get-AzResourceGroup -Name $rg -ErrorAction Stop

Write-Host "Validar si el tag 'environment' existe" 

if (-not $resourceGroupName.Tags.ContainsKey("environment")) {
   throw "El recursos '$recurso' no cuenta con un ambiente definido."
}

Write-Host " Obtener el valor del tag"

$tagValue = $resourceGroupName.Tags["environment"].ToLower()

Write-Host "Determinar ambiente esperado según el tag"

switch ($tagValue) {
    "prod" { $ambienteEsperado = "Producción" }
    "desa" { $ambienteEsperado = "Desarrollo" }
    "cert" { $ambienteEsperado = "Certificación" }
    default {
        throw "El recursos '$recurso' no cuenta con un ambiente definido."
    }
}

$grupodered = $Request.body.grupodered
$rol= $Request.body.rol

Write-Host "Validar que el grupo contenga el código de aplicación"
if ($grupodered -notmatch $codapp) {
    throw "El grupo '$grupodered' no corresponde al '$codapp'."
} 

Write-Host "Validando si el grupo de red esta restringido"
$grRestringidos = @(
   "POAZ_DEV_${codApp}_DESA"
   "POAZ_LT_${codApp}_DESA"
   "POAZ_LT_${codApp}_CERT"
   "POAZ_QA_${codApp}_CERT"
)

# ejecutando condicion

if ($grRestringidos -contains $grupodered) {
   throw "El grupo de red '$grupodered' no esta permitido para este tipo de solicitud"
} 

Write-Host "Validar si el grupo termina con prod_poaz, cert_poaz o desa_poaz"
if (
    $grupodered -notlike '*_prod_poaz' -and
    $grupodered -notlike '*_cert_poaz' -and
    $grupodered -notlike '*_desa_poaz'
) {
    throw "El grupo '$grupodered' no es un grupo 'POAZ' adicional de aplicación, favor de ingresar un grupo 'POAZ' valido."
}

Write-Host "Validar que el grupo coincida con el ambiente según sufijo"
switch ($true) {
    { $grupodered -like '*_prod_poaz' -and $ambiente -ne 'Producción' } {
        throw "El grupo es productivo, pero el ambiente no es 'producción'."
    }
    { $grupodered -like '*_cert_poaz' -and $ambiente -ne 'Certificación' } {
        throw "El grupo es de certificación, pero el ambiente no es 'certificación'."
    }
    { $grupodered -like '*_desa_poaz' -and $ambiente -ne 'Desarrollo' } {
        throw "El grupo es de desarrollo, pero el ambiente no es 'desarrollo'."
    }
    default {
        Write-Host "El grupo '$grupodered' corresponde al ambiente '$ambiente'."
    }
}

Write-Host "Validando si existe el Grupo de Red"
$group = Get-AzADGroup -DisplayName $grupodered -ErrorAction SilentlyContinue
# Validar si existe
if (-not $group) {
   throw "El grupo de red '$grupodered' no existe en Azure AD."
}

$resource = Get-AzResource -Name $recurso -ResourceGroupName $rg -ErrorAction SilentlyContinue
 if(-not $resource){
throw "El recurso '$recurso' no existe en el grupo de recursos '$rg'."
 }

$idgrupodered = (Get-AzADGroup -DisplayName $grupodered).id

Write-Host "Validando si el rol esta restringido"
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
   "Rol Networking Whitelist - Ambientes Previos"
   "Developer Environment Operator"
   "Environment Operator"
   "Reader Environment Certi"
   "Reader Certi QA"
)
# ejecutando condicion

if ($rolesRestringidos -contains $rol) {
   throw "El Rol '$rol' no esta permitido solicitarlo por este medio, se procede a cancelar la solicitud"
} 

Write-Host "validar si el rol existe a nivel de suscripçion"

$role = Get-AzRoleDefinition | Where-Object {$_.Name -eq $rol}
# Verificar si la suscripción está en los ámbitos asignables
if ($role) {
  Write-Host "El rol '$rol' está disponible para la suscripción '$suscripcion'."
}else {
   throw "El rol '$rol' NO está disponible para la suscripción '$suscripcion'."
}

$idresource = Get-AzResource -ResourceGroupName $rg -Name $recurso
$idrecurso = $idresource.ResourceId
$tiporecurso = $Request.Body.tiporecurso
# Verificar si ya existe la asignación
$asignacion = Get-AzRoleAssignment -Scope $idrecurso -ObjectId $idgrupodered -ErrorAction SilentlyContinue | Where-Object {
   $_.RoleDefinitionName -eq $rol
}
if ($null -ne $asignacion) {
   Write-Host "Ya existe una asignación del rol '$rol' para el grupo de red '$grupodered'."
}


$azureServices = @{
    "API Management"               = "Microsoft.ApiManagement/service"
    "App Service plan"            = "Microsoft.Web/serverfarms"
    "Application gateway"         = "Microsoft.Network/applicationGateways"
    "Application Insights"        = "Microsoft.Insights/components"
    "Azure Function"              = "Microsoft.Web/sites"
    "Automation Account"          = "Microsoft.Automation/automationAccounts"
    "Container registry"          = "Microsoft.ContainerRegistry/registries"
    "Azure Data Explorer Cluster" = "Microsoft.Kusto/Clusters"
    "Azure Databricks"            = "Microsoft.Databricks/workspaces"
    "DNS zone"                    = "Microsoft.Network/dnszones"
    "Event Hub"                   = "Microsoft.EventHub/namespaces"
    "Event Grid Topic"            = "Microsoft.EventGrid/topics"
    "Event Grid System Topic"     = "Microsoft.EventGrid/systemTopics"
    "Front Door and CDN profile"  = "Microsoft.Cdn/profiles"
    "Kubernetes service"          = "Microsoft.ContainerService/managedClusters"
    "Key vault"                   = "Microsoft.KeyVault/vaults"
    "Storage account"             = "Microsoft.Storage/storageAccounts"
    "SQL server"                  = "Microsoft.Sql/servers"
    "Azure Cosmos DB"             = "Microsoft.DocumentDB/databaseAccounts"
    "Azure Cache for Redis"       = "Microsoft.Cache/Redis"
    "Web App"                     = "Microsoft.Web/sites"
    "Virtual network"             = "Microsoft.Network/virtualNetworks"
    "Data factory"                = "Microsoft.DataFactory/factories"
    "Log Analytics"               = "Microsoft.OperationalInsights/workspaces"
    "Logic app"                   = "Microsoft.Logic/workflows"
    "Virtual machine"             = "Microsoft.Compute/virtualMachines"
    "Azure Bot"                   = "Microsoft.BotService/botServices"
}

# Validar si existe
if ($azureServices.ContainsKey($tiporecurso)) {
    $resourceType = $azureServices[$tiporecurso]
    Write-Host "Resource Type de '$tiporecurso' es: $resourceType"
}


#validar si es un rol temporal o permanente y realizar la asignación
$tipoAsignacion= $Request.body.duracion

if ($tipoAsignacion -eq "Permanente") {

#Asignar rol para la  suscripçion
Write-Host "Asignando rol en el recurso"
New-AzRoleAssignment -ObjectId $idgrupodered -RoleDefinitionName $rol -ResourceGroupName $rg -ResourceName $recurso -ResourceType $resourcetype

Write-Host "Se agrego el rol '$rol' permanete correspondiente al grupo de red '$grupodered' en el recurso '$recurso'"

# Confirmación de éxito
    $body = "Asignación de rol '$rol' Permanente de manera exitosa en el recurso '$recurso'"
}

elseif ($tipoAsignacion -eq "Temporal") {
$horaPeruTextoini = $Request.body.fechainicio
$horaPeruTextofin = $Request.body.fechafin
Write-Host "fecha inicio '$horaPeruTextoini'"
Write-Host "fecha fin '$horaPeruTextofin'"
$horaPeruTextoiniRecortada = $horaPeruTextoini -replace '\.\d{3}-\d{4}$', ''
Write-Host "fecha inicio2 '$horaPeruTextoiniRecortada'"
$horaPeruTextofinRecortada = $horaPeruTextofin -replace '\.\d{3}-\d{4}$', ''
Write-Host "fecha fin2 '$horaPeruTextofinRecortada'"
$horaUTCini = [datetime]::ParseExact($horaPeruTextoiniRecortada, "MM/dd/yyyy HH:mm:ss", $null)
$horaUTCini2 = [datetime]::SpecifyKind($horaUTCini, [System.DateTimeKind]::Utc)
Write-Host "fecha inicio 3 '$horaUTCini'"
Write-Host "fecha inicio 4 '$horaUTCini2'"
$horaUTCfin = [datetime]::ParseExact($horaPeruTextofinRecortada, "MM/dd/yyyy HH:mm:ss", $null)
$horaUTCfin2 = [datetime]::SpecifyKind($horaUTCfin, [System.DateTimeKind]::Utc)
Write-Host "fecha fin 3 '$horaUTCfin'"
Write-Host "fecha fin 4 '$horaUTCfin2'"
# Paso 2: (Opcional) Convertir a hora Perú solo para mostrar/log
$zonaPeru = [System.TimeZoneInfo]::FindSystemTimeZoneById("SA Pacific Standard Time")
$horaPeruini = [System.TimeZoneInfo]::ConvertTimeFromUtc($horaUTCini, $zonaPeru)
$horaPerufin = [System.TimeZoneInfo]::ConvertTimeFromUtc($horaUTCfin, $zonaPeru)
Write-Host "Hora Perú inicio: $horaPeruini"
Write-Host "Hora Perú fin: $horaPerufin"

$guid = [guid]::NewGuid().ToString()
$inicio= $horaUTCini2
$fin= $horaUTCfin2
$startTime = Get-Date $inicio -Format o  # Specify your start time here
$endTime = Get-Date $fin -Format o    # Specify your end time here
$rolId = (Get-AzRoleDefinition -Name $rol).Id
$Justification = "Asignación de rol temporal por medio de Plantilla ITSM Automatizada"

New-AzRoleAssignmentScheduleRequest -Name $guid -Scope "/subscriptions/$IdSuscripcion/resourceGroups/$rg/providers/$resourcetype/$recurso" -ExpirationType AfterDateTime -PrincipalId $idgrupodered -RequestType AdminAssign -RoleDefinitionId "/providers/Microsoft.Authorization/roleDefinitions/$rolId" -ScheduleInfoStartDateTime $startTime -ExpirationEndDateTime  $endTime -Justification $Justification 

Write-Host "Se agrego el rol '$rol' correspondiente al grupo de red '$grupodered' en el recurso '$recurso' de manera temporal"

# Confirmación de éxito
    $body = "Asignación de rol '$rol' temporal de manera exitosa en el recurso '$recurso' (Vigencia: $($horaPeruini.ToString('dd/MM/yyyy HH:mm:ss')) hasta $($horaPerufin.ToString('dd/MM/yyyy HH:mm:ss')) )"

}

}
catch {
    # Manejo de errores
    Write-Host "Error: $_"
    $body = $_.Exception.Message
    $statusCode = [HttpStatusCode]::BadRequest
}

# Respuesta HTTP
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = $statusCode
    Body = $body
})