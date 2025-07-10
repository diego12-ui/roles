using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

$body = ""
$statusCode = [HttpStatusCode]::OK
$codapp= $Request.Body.codapp
$mg = $Request.Body.managementgroup
$ambiente = $Request.Body.ambiente

try {
    # Validación de campos en el body
    if (-not $mg) {
        throw "No se encontró el Nombre del Management Group."
    }

if ($ambiente -ne "Producción") {
   throw "El ambiente debe ser productivo para este tipo de solicitud."
}
 
Write-Host "Iniciando sesión en Azure con Managed Identity..."
    Connect-AzAccount -Identity

$grupodered = $Request.body.grupodered

Write-Host "Validando si existe el Grupo de Red"
$group = Get-AzADGroup -DisplayName $grupodered -ErrorAction SilentlyContinue
# Validar si existe

if (-not $group) {
   throw "El grupo de red '$grupodered' no existe en Azure AD."
}

Write-Host "Validar que el grupo corresponda a 'POAZ'."
if ($grupodered -notlike 'POAZ_*') {
    throw "El grupo '$grupodered' no corresponde a un grupo 'POAZ', favor de ingresar un grupo 'POAZ' valido." 
}

Write-Host "Validar que el grupo corresponda a 'POAZ CROSS'."
if ($grupodered -notlike 'POAZ_SOPORTE_*' -and $grupodered -notlike 'POAZ_OPERATOR_*'-and $grupodered -notlike 'POAZ_READER_*' -and $grupodered -notlike 'POAZ_NET_*') {
    throw "El grupo '$grupodered' no corresponde a un grupo 'POAZ' cross, favor de ingresar un grupo 'POAZ' valido." 
}

Write-Host "Validar que el grupo corresponda a 'PROD'."
if ($grupodered -notlike '*_PROD') {
    throw "El grupo '$grupodered' no corresponde a un grupo 'POAZ PROD' cross, favor de ingresar un grupo 'POAZ' valido." 
}

$idgrupodered = (Get-AzADGroup -DisplayName $grupodered).id
$rol= $Request.body.rol
$tipoAsignacion= $Request.body.duracion

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

if ($rolesRestringidos -contains $rol) {
   throw "El Rol '$rol' no esta permitido solicitarlo por este medio, se procede a cancelar la solicitud"
} 

Write-Host "Verificando si el grupo de red ya cuenta con el rol en el Management Group"

$assignments = Get-AzRoleAssignment -ObjectId $idgrupodered -Scope "/providers/Microsoft.Management/managementGroups/$mg"
$Assigned = $assignments | Where-Object { $_.RoleDefinitionName -eq $rol }
if ($Assigned) {
   Write-Host "El Grupo de Red '$idgrupodered' ya tiene el rol '$rol' asignado a nivel de Management Group."
}

if ($tipoAsignacion -eq "Permanente") {

#Asignar rol para la  suscripçion
Write-Host "Asignando rol en el management group"
New-AzRoleAssignment -ObjectId $idgrupodered -RoleDefinitionName $rol -Scope "/providers/Microsoft.Management/managementGroups/$mg"

Write-Host "Se agrego el rol '$rol' permanete correspondiente al grupo de red '$grupodered' en el management group '$mg'"

# Confirmación de éxito
    $body = "Asignación de rol '$rol' Permanente de manera exitosa en el management group '$mg'"
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
Write-Host "Hora asignación inicio: $startTime"
Write-Host "Hora asignación fin: $endTime"
$rolId = (Get-AzRoleDefinition -Name $rol).Id
$Justification = "Asignación de rol temporal por medio de Plantilla ITSM Automatizada"

New-AzRoleAssignmentScheduleRequest -Name $guid -Scope "/providers/Microsoft.Management/managementGroups/$mg" -ExpirationType AfterDateTime -PrincipalId $idgrupodered -RequestType AdminAssign -RoleDefinitionId "/providers/Microsoft.Authorization/roleDefinitions/$rolId" -ScheduleInfoStartDateTime $startTime -ExpirationEndDateTime  $endTime -Justification $Justification 

Write-Host "Se agrego el rol '$rol' correspondiente al grupo de red '$grupodered' en el management group '$mg'"

# Confirmación de éxito
    $body = "Asignación de rol '$rol' temporal de manera exitosa en el management group '$mg' (Vigencia: $($horaPeruini.ToString('dd/MM/yyyy HH:mm:ss')) hasta $($horaPerufin.ToString('dd/MM/yyyy HH:mm:ss')) )"

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


