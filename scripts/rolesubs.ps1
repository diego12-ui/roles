using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

$body = ""
$statusCode = [HttpStatusCode]::OK
$codapp= $Request.Body.codapp
$suscripcion = $Request.Body.suscription
$ambiente = $Request.Body.ambiente

try {
    # Validación de campos en el body
    if (-not $suscripcion) {
        throw "No se encontró el Nombre de la Suscripcion."
    }
 
if ($ambiente -ne "Producción") {
   throw "El ambiente debe ser productivo para este tipo de solicitud."
}

Write-Host "Iniciando sesión en Azure con Managed Identity..."
    Connect-AzAccount -Identity

#Validando que la suscripcion corresponda al codigo de aplicación
Write-Host "Validando que la suscripcion corresponda al codigo de aplicación"
if ($suscripcion -notlike "*$codapp*") {
   throw "El codigo de aplicación '$codapp' no corresponde a la suscripción '$suscripcion'."
}


Write-Host "Validando que la suscripcion exista en Azure"
$IdSuscripcion = (Get-AzSubscription -SubscriptionName $suscripcion).id
if ( -not $IdSuscripcion){
throw "La suscripcion no existe."
}

Write-Host  "Lista de suscripciones no permitidas"
$noPermitidas = @(
    "DTI - INF - INFR - Servicios Compartidos",
    "Azure EA - Credicorp"
)
 
Write-Host "Validación de suscripciones no permitidas"
if ($noPermitidas -contains $suscripcion) {
    throw "La solicitud no será atendida, no esta permitida la asinación de roles para la suscripción '$suscripcion'."
}

Set-AzContext -Subscription $IdSuscripcion -Force

$grupodered = $Request.body.grupodered

Write-Host "Validando si existe el Grupo de Red"
$group = Get-AzADGroup -DisplayName $grupodered -ErrorAction SilentlyContinue
# Validar si existe

if (-not $group) {
   throw "El grupo de red '$grupodered' no existe en Azure AD."
}


$rol= $Request.body.rol

# Construcción de nombres válidos
$costGroup = "POAZ_COSTMANAGEMENT_$codapp"
$dashGroup = "POAZ_DASHBOARD_$codapp"

Write-Host "Validando rol permitido"
if ($rol -ne "Cost Management Reader" -and $rol -ne "Dashboard Reader") {
    throw "Rol no válido: '$rol'. Solo se permiten 'Cost Management Reader' o 'Dashboard Reader'."
}

Write-Host "Validando grupo de red permitido"
if ($grupodered -ne $costGroup -and $grupodered -ne $dashGroup) {
    throw "Grupo de red no válido: '$grupodered'. Debe ser '$costGroup' o '$dashGroup'."
}

Write-Host "Validar consistencia entre grupo de red y rol asignado"
if ($grupodered -eq $costGroup -and $rol -ne "Cost Management Reader") {
    throw "Se ingreso el rol '$rol' de manera incorrecta, el grupo '$grupodered' requiere el rol 'Cost Management Reader'."
}
elseif ($grupodered -eq $dashGroup -and $rol -ne "Dashboard Reader") {
    throw "Se ingreso el rol '$rol' de manera incorrecta, El grupo '$grupodered' requiere el rol 'Dashboard Reader'."
}

$idgrupodered = (Get-AzADGroup -DisplayName $grupodered).id

Write-Host "Validando si el rol esta restringido"
$rolesRestringidos = @(
   "Owner",
   "Contributor",
   "User Access Administrator",
   "Azure File Sync Administrator",
   "Custom_Rol_BotServices_Automation_CDAI_PROD",
   "Custom_Rol_Databricks_Workspace_Automation_CDAI_PROD",
   "Orca Security - Dedicated Resource Group Creator Role v13.00.00 / nc5srtx3f35n4",
   "Orca Security - Key Vault Updater Role v13.00.00 / nc5srtx3f35n4",
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

#validar si la suscripcion ya cuenta con el grupo de red
Write-Host "Verificando si el Grupo de Red ya cuenta con el rol en la suscripcion"

$assignments = Get-AzRoleAssignment -ObjectId $idgrupodered -Scope "/subscriptions/$IdSuscripcion"
$Assigned = $assignments | Where-Object { $_.RoleDefinitionName -eq $rol }
if ($Assigned) {
   Write-Host "El grupo '$grupodered' ya tiene el rol '$rol' asignado a nivel de suscripción."
}

#validar si es un rol temporal o permanente y realizar la asignación
$tipoAsignacion= $Request.body.duracion

if ($tipoAsignacion -eq "Permanente") {

#Asignar rol para la  suscripçion
Write-Host "Asignando rol en la suscripcion"
New-AzRoleAssignment -ObjectId $idgrupodered -RoleDefinitionName $rol -Scope "/subscriptions/$IdSuscripcion"

Write-Host "Se agrego el rol '$rol' permanete correspondiente al grupo de red '$grupodered' en la suscripcion '$suscripcion'"

# Confirmación de éxito
    $body = "Asignación de rol '$rol' Permanente de manera exitosa en la suscripcion '$suscripcion'"
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

New-AzRoleAssignmentScheduleRequest -Name $guid -Scope "/subscriptions/$IdSuscripcion" -ExpirationType AfterDateTime -PrincipalId $idgrupodered -RequestType AdminAssign -RoleDefinitionId "/providers/Microsoft.Authorization/roleDefinitions/$rolId" -ScheduleInfoStartDateTime $startTime -ExpirationEndDateTime  $endTime -Justification $Justification 

Write-Host "Se agrego el rol '$rol' correspondiente al grupo de red '$grupodered' en la suscripcion '$suscripcion' de manera temporal"

# Confirmación de éxito
    $body = "Asignación de rol '$rol' temporal de manera exitosa en la suscripcion '$suscripcion' (Vigencia: $($horaPeruini.ToString('dd/MM/yyyy HH:mm:ss')) hasta $($horaPerufin.ToString('dd/MM/yyyy HH:mm:ss')) )"

}

}catch {
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