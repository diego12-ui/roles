# Script parametrizado para asignar/eliminar roles de Managed Identity
# Para integración con JIRA Service Management
# Requiere: Az PowerShell Module

param(
    # Operación a realizar
    [Parameter(Mandatory=$true)]
    [ValidateSet("Asignar Rol", "Eliminar Rol")]
    [string]$Operacion,
    
    # Configuración del recurso origen (Managed Identity)
    [Parameter(Mandatory=$true)]
    [string]$RecursoOrigenNombre,
    
    [Parameter(Mandatory=$true)]
    [string]$RecursoOrigenTipo,
    
    [Parameter(Mandatory=$true)]
    [string]$RecursoOrigenSuscripcion,
    
    [Parameter(Mandatory=$true)]
    [string]$RecursoOrigenResourceGroup,
    
    # Configuración del ámbito
    [Parameter(Mandatory=$true)]
    [ValidateSet("ManagementGroup", "Recurso", "Suscripción", "Grupo de Recursos")]
    [string]$TipoAmbito,
    
    # Para Management Group
    [Parameter(Mandatory=$false)]
    [string]$ManagementGroupNombre,
    
    # Para Recurso Específico
    [Parameter(Mandatory=$false)]
    [string]$RecursoDestinoNombre,
    
    [Parameter(Mandatory=$false)]
    [string]$RecursoDestinoTipo,
    
    [Parameter(Mandatory=$false)]
    [string]$RecursoDestinoSuscripcion,
    
    [Parameter(Mandatory=$false)]
    [string]$RecursoDestinoResourceGroup,
    
    # Para Storage Account - Contenedor específico
    [Parameter(Mandatory=$false)]
    [ValidateSet("Si", "No")]
    [string]$UsarContenedorEspecifico = "No",
    
    [Parameter(Mandatory=$false)]
    [string]$ContenedorNombre,
    
    # Para Virtual Network - Subnet específica
    [Parameter(Mandatory=$false)]
    [ValidateSet("Si", "No")]
    [string]$UsarSubnetEspecifica = "No",
    
    [Parameter(Mandatory=$false)]
    [string]$SubnetNombre,
    
    # Configuración del rol
    [Parameter(Mandatory=$false)]
    [string]$RolNombre,
    
    # Para eliminación - ID de asignación específica (opcional)
    [Parameter(Mandatory=$false)]
    [string]$AsignacionIdAEliminar,
    
    # Modo de ejecución
    [Parameter(Mandatory=$false)]
    [ValidateSet("Interactivo", "Automatico")]
    [string]$ModoEjecucion = "Automatico"
)

# Función para detectar ambiente por nomenclatura
function Get-EnvironmentFromResourceName {
    param([string]$ResourceName)
    
    if ($ResourceName.Length -lt 3) {
        throw "El nombre del recurso '$ResourceName' es muy corto para determinar el ambiente"
    }
    
    $environmentLetter = $ResourceName[-3]
    
    switch ($environmentLetter.ToLower()) {
        'd' { return "Desarrollo" }
        'c' { return "Certificación" }
        'p' { return "Producción" }
        default { 
            throw "No se pudo determinar el ambiente del recurso '$ResourceName'. Antepenúltima letra: '$environmentLetter'"
        }
    }
}

# Función para validar roles restringidos
function Test-RestrictedRole {
    param([string]$RoleName)
    
    $rolesRestringidos = @(
        "Owner", "Contributor", "User Access Administrator", "Reservations Administrator",
        "Access Review Operator Service Role", "Role Based Access Control Administrator",
        "Service Group Contributor", "Administrador IBM Cloud", "Environment Automation",
        "Environment Automation II", "Rol Administrador de Accesos", "Rol Administrador de Accesos PIM",
        "Administrador Modelo Soporte", "Environment Operator APIM", "Rol Modificar NSG SOAR",
        "Rol Networking Whitelist - Ambientes Previos", "Developer Environment Operator",
        "Environment Operator", "Reader Environment Certi", "Reader Certi QA"
    )
    
    if ($rolesRestringidos -contains $RoleName) {
        throw "El Rol '$RoleName' no está permitido solicitarlo por este medio"
    }
    
    return $true
}

# Función principal
function Invoke-ManagedIdentityRoleManagement {
    Write-Host "=== MANAGED IDENTITY ROLE MANAGEMENT - MODO JIRA ===" -ForegroundColor Green
    Write-Host "Operación: $Operacion" -ForegroundColor Cyan
    Write-Host "Modo: $ModoEjecucion" -ForegroundColor Cyan

    # Verificar conexión a Azure
    try {
        $context = Get-AzContext
        if (-not $context) {
            Write-Host "Conectando a Azure..." -ForegroundColor Yellow
            Connect-AzAccount
        }
        Write-Host "✅ Conectado a Azure - Tenant: $($context.Tenant.Id)" -ForegroundColor Green
    }
    catch {
        Write-Error "Error al conectar con Azure: $($_.Exception.Message)"
        return
    }

    # Validar parámetros según el tipo de ámbito
    if ($TipoAmbito -eq "ManagementGroup" -and [string]::IsNullOrEmpty($ManagementGroupNombre)) {
        throw "Para ámbito ManagementGroup se requiere ManagementGroupNombre"
    }
    
    if ($TipoAmbito -eq "RecursoEspecifico") {
        if ([string]::IsNullOrEmpty($RecursoDestinoNombre) -or [string]::IsNullOrEmpty($RecursoDestinoTipo) -or 
            [string]::IsNullOrEmpty($RecursoDestinoSuscripcion) -or [string]::IsNullOrEmpty($RecursoDestinoResourceGroup)) {
            throw "Para ámbito RecursoEspecifico se requieren todos los parámetros del recurso destino"
        }
    }

    # Detectar ambiente del recurso origen
    try {
        $sourceEnvironment = Get-EnvironmentFromResourceName -ResourceName $RecursoOrigenNombre
        Write-Host "✅ Ambiente detectado del recurso origen: $sourceEnvironment" -ForegroundColor Green
    }
    catch {
        Write-Error $_.Exception.Message
        return
    }

    # Validar suscripción origen
    $sourceSubscription = Get-AzSubscription -SubscriptionName $RecursoOrigenSuscripcion -ErrorAction SilentlyContinue
    if (-not $sourceSubscription) {
        Write-Error "Suscripción origen '$RecursoOrigenSuscripcion' no encontrada"
        return
    }

    Set-AzContext -SubscriptionId $sourceSubscription.Id | Out-Null

    # Obtener la Managed Identity del recurso origen
    Write-Host "Obteniendo Managed Identity del recurso '$RecursoOrigenNombre'..." -ForegroundColor Yellow

    try {
        $sourceResource = Get-AzResource -ResourceGroupName $RecursoOrigenResourceGroup -ResourceType $RecursoOrigenTipo -ResourceName $RecursoOrigenNombre -ErrorAction Stop

        $managedIdentityId = $null
        if ($sourceResource.Identity -and $sourceResource.Identity.PrincipalId) {
            $managedIdentityId = $sourceResource.Identity.PrincipalId
            Write-Host "✅ System-Assigned Managed Identity encontrada: $managedIdentityId" -ForegroundColor Green
        } else {
            throw "No se encontró Managed Identity en el recurso '$RecursoOrigenNombre'"
        }
    } catch {
        Write-Error "Error al obtener el recurso origen: $($_.Exception.Message)"
        return
    }

    # Construir el scope de destino
    $targetScope = ""
    $targetEnvironment = ""

    if ($TipoAmbito -eq "ManagementGroup") {
        $targetScope = "/providers/Microsoft.Management/managementGroups/$ManagementGroupNombre"
        Write-Host "Ámbito: Management Group '$ManagementGroupNombre'" -ForegroundColor White
    } else {
        # Validar ambiente del recurso destino (solo para asignación)
        if ($Operacion -eq "Asignar") {
            try {
                $targetEnvironment = Get-EnvironmentFromResourceName -ResourceName $RecursoDestinoNombre
                Write-Host "✅ Ambiente detectado del recurso destino: $targetEnvironment" -ForegroundColor Green
                
                if ($sourceEnvironment -ne $targetEnvironment) {
                    throw "Los recursos deben pertenecer al mismo ambiente. Origen: '$sourceEnvironment', Destino: '$targetEnvironment'"
                }
                Write-Host "✅ Validación de ambiente exitosa" -ForegroundColor Green
            }
            catch {
                Write-Error $_.Exception.Message
                return
            }
        }

        # Validar suscripción destino
        $targetSubscription = Get-AzSubscription -SubscriptionName $RecursoDestinoSuscripcion -ErrorAction SilentlyContinue
        if (-not $targetSubscription) {
            Write-Error "Suscripción destino '$RecursoDestinoSuscripcion' no encontrada"
            return
        }

        # Construir scope base
        $targetScope = "/subscriptions/$($targetSubscription.Id)/resourceGroups/$RecursoDestinoResourceGroup/providers/$RecursoDestinoTipo/$RecursoDestinoNombre"

        # Ajustar scope para Storage Account con contenedor
        if ($RecursoDestinoTipo -eq "Microsoft.Storage/storageAccounts" -and $UsarContenedorEspecifico -eq "Si") {
            if ([string]::IsNullOrEmpty($ContenedorNombre)) {
                throw "Para usar contenedor específico se requiere ContenedorNombre"
            }
            $targetScope = "$targetScope/blobServices/default/containers/$ContenedorNombre"
            Write-Host "Ámbito: Contenedor '$ContenedorNombre' en Storage Account '$RecursoDestinoNombre'" -ForegroundColor White
        }
        # Ajustar scope para Virtual Network con subnet
        elseif ($RecursoDestinoTipo -eq "Microsoft.Network/virtualNetworks" -and $UsarSubnetEspecifica -eq "Si") {
            if ([string]::IsNullOrEmpty($SubnetNombre)) {
                throw "Para usar subnet específica se requiere SubnetNombre"
            }
            $targetScope = "$targetScope/subnets/$SubnetNombre"
            Write-Host "Ámbito: Subnet '$SubnetNombre' en Virtual Network '$RecursoDestinoNombre'" -ForegroundColor White
        }
        else {
            Write-Host "Ámbito: Recurso completo '$RecursoDestinoNombre'" -ForegroundColor White
        }
    }

    # Ejecutar operación
    if ($Operacion -eq "Asignar") {
        # Validar que se proporcionó el rol
        if ([string]::IsNullOrEmpty($RolNombre)) {
            throw "Para asignación se requiere RolNombre"
        }

        # Validar roles restringidos
        try {
            Test-RestrictedRole -RoleName $RolNombre
            Write-Host "✅ Validación de rol exitosa" -ForegroundColor Green
        }
        catch {
            Write-Error $_.Exception.Message
            return
        }

        # Verificar asignaciones existentes
        Write-Host "Verificando asignaciones existentes..." -ForegroundColor Yellow
        try {
            $existingAssignments = Get-AzRoleAssignment -ObjectId $managedIdentityId -Scope $targetScope -ErrorAction SilentlyContinue
            $existingRole = $existingAssignments | Where-Object { $_.RoleDefinitionName -eq $RolNombre }

            if ($existingRole) {
                if ($ModoEjecucion -eq "Interactivo") {
                    Write-Warning "La Managed Identity ya tiene el rol '$RolNombre' asignado en este ámbito."
                    $continue = Read-Host "¿Continuar de todas formas? (y/N)"
                    if ($continue -ne "y" -and $continue -ne "Y") {
                        Write-Host "Operación cancelada." -ForegroundColor Yellow
                        return
                    }
                } else {
                    Write-Warning "La Managed Identity ya tiene el rol '$RolNombre' asignado. Continuando..."
                }
            }
        } catch {
            Write-Host "No se pudieron verificar asignaciones existentes. Continuando..." -ForegroundColor Yellow
        }

        # Mostrar resumen
        Write-Host "`n=== RESUMEN DE ASIGNACIÓN ===" -ForegroundColor Magenta
        Write-Host "➕ OPERACIÓN: ASIGNAR ROL" -ForegroundColor Green
        Write-Host "Recurso Origen: $RecursoOrigenNombre ($RecursoOrigenTipo)" -ForegroundColor White
        Write-Host "Ambiente Origen: $sourceEnvironment" -ForegroundColor White
        Write-Host "Managed Identity ID: $managedIdentityId" -ForegroundColor White
        Write-Host "Rol: $RolNombre" -ForegroundColor White
        Write-Host "Scope Path: $targetScope" -ForegroundColor White

        # Ejecutar asignación
        Write-Host "`nEjecutando asignación de rol..." -ForegroundColor Yellow
        try {
            $assignment = New-AzRoleAssignment -ObjectId $managedIdentityId -RoleDefinitionName $RolNombre -Scope $targetScope

            Write-Host "`n✅ ¡Asignación completada exitosamente!" -ForegroundColor Green
            Write-Host "Assignment ID: $($assignment.RoleAssignmentId)" -ForegroundColor Cyan
            Write-Host "La Managed Identity del recurso '$RecursoOrigenNombre' ahora tiene el rol '$RolNombre'" -ForegroundColor Green

        } catch {
            Write-Error "Error al crear la asignación: $($_.Exception.Message)"
            throw
        }

    } else {
        # Operación de eliminación
        Write-Host "`n=== RESUMEN DE ELIMINACIÓN ===" -ForegroundColor Magenta
        Write-Host "🗑️  OPERACIÓN: ELIMINAR ROL" -ForegroundColor Red
        Write-Host "Recurso Origen: $RecursoOrigenNombre ($RecursoOrigenTipo)" -ForegroundColor White
        Write-Host "Ambiente Origen: $sourceEnvironment" -ForegroundColor White
        Write-Host "Managed Identity ID: $managedIdentityId" -ForegroundColor White
        Write-Host "Scope Path: $targetScope" -ForegroundColor White

        # Si se especificó un rol específico, eliminarlo
        if (-not [string]::IsNullOrEmpty($RolNombre)) {
            Write-Host "Rol a eliminar: $RolNombre" -ForegroundColor White
            
            Write-Host "`nEliminando asignación de rol..." -ForegroundColor Yellow
            try {
                Remove-AzRoleAssignment -ObjectId $managedIdentityId -RoleDefinitionName $RolNombre -Scope $targetScope -ErrorAction Stop
                
                Write-Host "`n✅ ¡Asignación eliminada exitosamente!" -ForegroundColor Green
                Write-Host "Se eliminó el rol '$RolNombre' de la Managed Identity del recurso '$RecursoOrigenNombre'" -ForegroundColor Green
                
            } catch {
                Write-Error "Error al eliminar la asignación: $($_.Exception.Message)"
                throw
            }
        } else {
            # Listar asignaciones existentes para selección manual
            try {
                $assignments = Get-AzRoleAssignment -ObjectId $managedIdentityId -Scope $targetScope -ErrorAction Stop
                
                if ($assignments.Count -eq 0) {
                    Write-Warning "No se encontraron asignaciones de roles para esta Managed Identity en el ámbito especificado."
                    return
                }
                
                Write-Host "`nAsignaciones encontradas:" -ForegroundColor Cyan
                foreach ($assignment in $assignments) {
                    Write-Host "• $($assignment.RoleDefinitionName) - ID: $($assignment.RoleAssignmentId)" -ForegroundColor Yellow
                }
                
                if ($ModoEjecucion -eq "Interactivo") {
                    Write-Host "`nEspecifica el nombre exacto del rol a eliminar o usa el parámetro -RolNombre" -ForegroundColor Yellow
                } else {
                    Write-Warning "En modo automático se requiere especificar -RolNombre para eliminación"
                }
                
            } catch {
                Write-Error "Error al obtener asignaciones existentes: $($_.Exception.Message)"
                throw
            }
        }
    }
}

# Ejecutar la función principal
try {
    Invoke-ManagedIdentityRoleManagement
    Write-Host "`n✅ Script ejecutado exitosamente" -ForegroundColor Green
} catch {
    Write-Error "Error en la ejecución del script: $($_.Exception.Message)"
    exit 1
}