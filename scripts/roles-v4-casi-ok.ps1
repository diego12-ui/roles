# Script para asignar y eliminar roles de Managed Identity entre recursos
# Requiere: Az PowerShell Module

function Show-Menu {
    param([string]$Title, [array]$Options)

    Write-Host "`n=== $Title ===" -ForegroundColor Cyan
    for ($i = 0; $i -lt $Options.Length; $i++) {
        Write-Host "$($i + 1). $($Options[$i])" -ForegroundColor Yellow
    }

    do {
        $selection = Read-Host "`nSelecciona una opción (1-$($Options.Length))"
        $index = [int]$selection - 1
    } while ($index -lt 0 -or $index -ge $Options.Length)

    return $Options[$index]
}

# Función para detectar ambiente por nomenclatura
function Get-EnvironmentFromResourceName {
    param([string]$ResourceName)
    
    if ($ResourceName.Length -lt 3) {
        throw "El nombre del recurso '$ResourceName' es muy corto para determinar el ambiente"
    }
    
    # Obtener la antepenúltima letra
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

# Función para validar roles restringidos (solo para asignación)
function Test-RestrictedRole {
    param([string]$RoleName)
    
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
    
    if ($rolesRestringidos -contains $RoleName) {
        throw "El Rol '$RoleName' no está permitido solicitarlo por este medio, se procede a cancelar la solicitud"
    }
    
    return $true
}

# Función para obtener contenedores de Storage Account
function Get-StorageContainers {
    param(
        [string]$StorageAccountName,
        [string]$ResourceGroupName,
        [string]$SubscriptionId
    )
    
    try {
        Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
        $storageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction Stop
        $ctx = $storageAccount.Context
        $containers = Get-AzStorageContainer -Context $ctx -ErrorAction Stop
        return $containers
    }
    catch {
        Write-Warning "No se pudieron obtener los contenedores: $($_.Exception.Message)"
        return $null
    }
}

# Función para obtener subnets de Virtual Network
function Get-VirtualNetworkSubnets {
    param(
        [string]$VNetName,
        [string]$ResourceGroupName,
        [string]$SubscriptionId
    )
    
    try {
        Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
        $vnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $VNetName -ErrorAction Stop
        return $vnet.Subnets
    }
    catch {
        Write-Warning "No se pudieron obtener las subnets: $($_.Exception.Message)"
        return $null
    }
}

# Función para listar asignaciones existentes y permitir selección
function Get-ExistingRoleAssignments {
    param(
        [string]$ManagedIdentityId,
        [string]$TargetScope
    )
    
    try {
        $assignments = Get-AzRoleAssignment -ObjectId $ManagedIdentityId -ErrorAction Stop
        
        # Filtrar por scope si se especifica
        if ($TargetScope) {
            $assignments = $assignments | Where-Object { $_.Scope -eq $TargetScope }
        }
        
        if ($assignments.Count -eq 0) {
            Write-Warning "No se encontraron asignaciones de roles para esta Managed Identity en el ámbito especificado."
            return $null
        }
        
        Write-Host "`nAsignaciones de roles existentes:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $assignments.Count; $i++) {
            $assignment = $assignments[$i]
            Write-Host "$($i + 1). $($assignment.RoleDefinitionName)" -ForegroundColor Yellow
            Write-Host "   Scope: $($assignment.Scope)" -ForegroundColor Gray
            Write-Host "   Assignment ID: $($assignment.RoleAssignmentId)" -ForegroundColor Gray
        }
        
        do {
            $selection = Read-Host "`nSelecciona la asignación a eliminar (1-$($assignments.Count))"
            $index = [int]$selection - 1
        } while ($index -lt 0 -or $index -ge $assignments.Count)
        
        return $assignments[$index]
        
    } catch {
        Write-Error "Error al obtener asignaciones existentes: $($_.Exception.Message)"
        return $null
    }
}

function New-ManagedIdentityRoleManagement {
    Write-Host "=== MANAGED IDENTITY ROLE MANAGEMENT ===" -ForegroundColor Green

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

    # Seleccionar operación
    Write-Host "`n--- SELECCIÓN DE OPERACIÓN ---" -ForegroundColor Cyan
    $operations = @("Asignar rol", "Eliminar rol")
    $selectedOperation = Show-Menu -Title "¿Qué operación deseas realizar?" -Options $operations
    
    $isRemovalOperation = ($selectedOperation -eq "Eliminar rol")
    
    if ($isRemovalOperation) {
        Write-Host "`n🗑️  MODO: ELIMINACIÓN DE ROL" -ForegroundColor Red
    } else {
        Write-Host "`n➕ MODO: ASIGNACIÓN DE ROL" -ForegroundColor Green
    }

    Write-Host "`n--- CONFIGURACIÓN DEL RECURSO ORIGEN (Managed Identity) ---" -ForegroundColor Cyan

    # 1. Obtener información del recurso origen
    $sourceResourceName = Read-Host "Nombre del recurso ORIGEN (ej: dafaeu2testd01)"
    
    # Detectar ambiente del recurso origen
    try {
        $sourceEnvironment = Get-EnvironmentFromResourceName -ResourceName $sourceResourceName
        Write-Host "✅ Ambiente detectado del recurso origen: $sourceEnvironment" -ForegroundColor Green
    }
    catch {
        Write-Error $_.Exception.Message
        return
    }

    $sourceSubscriptionName = Read-Host "Nombre de la Suscripción del recurso ORIGEN"
    $sourceRgName = Read-Host "Nombre del Resource Group del recurso ORIGEN"

    # Validar suscripción origen
    $sourceSubscription = Get-AzSubscription -SubscriptionName $sourceSubscriptionName -ErrorAction SilentlyContinue
    if (-not $sourceSubscription) {
        Write-Error "Suscripción origen '$sourceSubscriptionName' no encontrada"
        return
    }

    # Cambiar contexto a la suscripción origen
    Set-AzContext -SubscriptionId $sourceSubscription.Id | Out-Null

    # Tipos de recursos comunes con Managed Identity
    $resourceTypes = @(
        "Microsoft.DataFactory/factories",
        "Microsoft.Compute/virtualMachines",
        "Microsoft.Web/sites",
        "Microsoft.Logic/workflows",
        "Microsoft.Automation/automationAccounts",
        "Microsoft.ContainerInstance/containerGroups",
        "Microsoft.KeyVault/vaults",
        "Microsoft.Storage/storageAccounts",
        "Otro (especificar manualmente)"
    )

    $selectedResourceType = Show-Menu -Title "Tipo de Recurso ORIGEN" -Options $resourceTypes

    if ($selectedResourceType -eq "Otro (especificar manualmente)") {
        $sourceResourceType = Read-Host "Especifica el tipo de recurso (ej: Microsoft.DataFactory/factories)"
    } else {
        $sourceResourceType = $selectedResourceType
    }

    # 2. Obtener la Managed Identity del recurso origen
    Write-Host "`nObteniendo Managed Identity del recurso..." -ForegroundColor Yellow

    try {
        $sourceResource = Get-AzResource -ResourceGroupName $sourceRgName -ResourceType $sourceResourceType -ResourceName $sourceResourceName -ErrorAction Stop

        # Obtener la identidad del recurso
        $managedIdentityId = $null

        if ($sourceResource.Identity -and $sourceResource.Identity.PrincipalId) {
            $managedIdentityId = $sourceResource.Identity.PrincipalId
            Write-Host "✅ System-Assigned Managed Identity encontrada: $managedIdentityId" -ForegroundColor Green
        } else {
            # Intentar obtener User-Assigned Managed Identity
            Write-Host "No se encontró System-Assigned MI. Buscando User-Assigned..." -ForegroundColor Yellow

            $userAssignedIdentities = Get-AzUserAssignedIdentity -ResourceGroupName $sourceRgName -ErrorAction SilentlyContinue
            if ($userAssignedIdentities) {
                Write-Host "`nUser-Assigned Identities disponibles:" -ForegroundColor Cyan
                for ($i = 0; $i -lt $userAssignedIdentities.Count; $i++) {
                    Write-Host "$($i + 1). $($userAssignedIdentities[$i].Name)" -ForegroundColor Yellow
                }

                $selection = Read-Host "`nSelecciona la identidad (1-$($userAssignedIdentities.Count))"
                $selectedIdentity = $userAssignedIdentities[$selection - 1]
                $managedIdentityId = $selectedIdentity.PrincipalId
                Write-Host "✅ User-Assigned Managed Identity seleccionada: $($selectedIdentity.Name)" -ForegroundColor Green
            }
        }

        if (-not $managedIdentityId) {
            throw "No se encontró ninguna Managed Identity en el recurso '$sourceResourceName'"
        }

    } catch {
        Write-Error "Error al obtener el recurso origen: $($_.Exception.Message)"
        return
    }

    # Para eliminación, mostrar opción de listar todas las asignaciones
    if ($isRemovalOperation) {
        Write-Host "`n--- SELECCIÓN DE ASIGNACIÓN A ELIMINAR ---" -ForegroundColor Cyan
        $removalOptions = @("Eliminar de ámbito específico", "Ver todas las asignaciones y seleccionar")
        $selectedRemovalOption = Show-Menu -Title "¿Cómo deseas proceder?" -Options $removalOptions
        
        if ($selectedRemovalOption -eq "Ver todas las asignaciones y seleccionar") {
            $assignmentToRemove = Get-ExistingRoleAssignments -ManagedIdentityId $managedIdentityId
            if (-not $assignmentToRemove) {
                return
            }
            
            # Mostrar resumen de eliminación
            Write-Host "`n=== RESUMEN DE ELIMINACIÓN ===" -ForegroundColor Magenta
            Write-Host "Recurso Origen: $sourceResourceName ($sourceResourceType)" -ForegroundColor White
            Write-Host "Ambiente: $sourceEnvironment" -ForegroundColor White
            Write-Host "Managed Identity ID: $managedIdentityId" -ForegroundColor White
            Write-Host "Rol a eliminar: $($assignmentToRemove.RoleDefinitionName)" -ForegroundColor White
            Write-Host "Scope: $($assignmentToRemove.Scope)" -ForegroundColor White
            Write-Host "Assignment ID: $($assignmentToRemove.RoleAssignmentId)" -ForegroundColor White

            $confirm = Read-Host "`n¿Proceder con la eliminación? (y/N)"
            if ($confirm -ne "y" -and $confirm -ne "Y") {
                Write-Host "Operación cancelada." -ForegroundColor Yellow
                return
            }

            # Ejecutar eliminación
            Write-Host "`nEliminando asignación de rol..." -ForegroundColor Yellow
            try {
                Remove-AzRoleAssignment -ObjectId $managedIdentityId -RoleDefinitionName $assignmentToRemove.RoleDefinitionName -Scope $assignmentToRemove.Scope -ErrorAction Stop
                
                Write-Host "`n✅ ¡Asignación eliminada exitosamente!" -ForegroundColor Green
                Write-Host "Se eliminó el rol '$($assignmentToRemove.RoleDefinitionName)' de la Managed Identity del recurso '$sourceResourceName'" -ForegroundColor Green
                
            } catch {
                Write-Error "Error al eliminar la asignación: $($_.Exception.Message)"
            }
            return
        }
    }

    # 3. Seleccionar ámbito (para asignación o eliminación específica)
    Write-Host "`n--- CONFIGURACIÓN DEL ÁMBITO ---" -ForegroundColor Cyan
    $scopes = @("Management Group", "Recurso específico")
    $selectedScope = Show-Menu -Title "Ámbito de la operación" -Options $scopes

    $targetScope = ""
    $targetResourceName = ""
    $targetEnvironment = ""

    switch ($selectedScope) {
        "Management Group" {
            $mgName = Read-Host "`nNombre del Management Group"
            $targetScope = "/providers/Microsoft.Management/managementGroups/$mgName"
            Write-Host "Ámbito: Management Group '$mgName'" -ForegroundColor White
        }

        "Recurso específico" {
            Write-Host "`n--- CONFIGURACIÓN DEL RECURSO DESTINO ---" -ForegroundColor Cyan
            $targetResourceName = Read-Host "Nombre del recurso DESTINO (ej: staceu2testd01)"
            
            # Detectar ambiente del recurso destino (solo para asignación)
            if (-not $isRemovalOperation) {
                try {
                    $targetEnvironment = Get-EnvironmentFromResourceName -ResourceName $targetResourceName
                    Write-Host "✅ Ambiente detectado del recurso destino: $targetEnvironment" -ForegroundColor Green
                    
                    # Validar que ambos recursos sean del mismo ambiente
                    if ($sourceEnvironment -ne $targetEnvironment) {
                        throw "Los recursos deben pertenecer al mismo ambiente. Origen: '$sourceEnvironment', Destino: '$targetEnvironment'"
                    }
                    Write-Host "✅ Validación de ambiente exitosa: Ambos recursos son de '$sourceEnvironment'" -ForegroundColor Green
                    
                }
                catch {
                    Write-Error $_.Exception.Message
                    return
                }
            } else {
                # Para eliminación, solo detectar sin validar
                try {
                    $targetEnvironment = Get-EnvironmentFromResourceName -ResourceName $targetResourceName
                    Write-Host "✅ Ambiente detectado del recurso destino: $targetEnvironment" -ForegroundColor Green
                }
                catch {
                    Write-Warning "No se pudo detectar el ambiente del recurso destino, continuando..."
                    $targetEnvironment = "No detectado"
                }
            }

            $targetSubscriptionName = Read-Host "Nombre de la Suscripción del recurso DESTINO"
            $targetRgName = Read-Host "Nombre del Resource Group del recurso DESTINO"
            $targetResourceType = Read-Host "Tipo del recurso DESTINO (ej: Microsoft.Storage/storageAccounts)"

            $targetSubscription = Get-AzSubscription -SubscriptionName $targetSubscriptionName -ErrorAction SilentlyContinue
            if (-not $targetSubscription) {
                Write-Error "Suscripción destino '$targetSubscriptionName' no encontrada"
                return
            }

            # Validar que el recurso destino existe (solo para asignación)
            if (-not $isRemovalOperation) {
                Set-AzContext -SubscriptionId $targetSubscription.Id | Out-Null
                $targetResource = Get-AzResource -ResourceGroupName $targetRgName -ResourceType $targetResourceType -ResourceName $targetResourceName -ErrorAction SilentlyContinue
                if (-not $targetResource) {
                    Write-Error "El recurso destino '$targetResourceName' no existe en el Resource Group '$targetRgName'"
                    return
                }
            }

            # Configuración específica para Storage Account
            if ($targetResourceType -eq "Microsoft.Storage/storageAccounts") {
                Write-Host "`n--- CONFIGURACIÓN DE STORAGE ACCOUNT ---" -ForegroundColor Cyan
                $containerChoice = Read-Host "¿Desea operar a nivel de contenedor específico? (y/N)"
                
                if ($containerChoice -eq "y" -or $containerChoice -eq "Y") {
                    if (-not $isRemovalOperation) {
                        Write-Host "`nObteniendo contenedores disponibles..." -ForegroundColor Yellow
                        $containers = Get-StorageContainers -StorageAccountName $targetResourceName -ResourceGroupName $targetRgName -SubscriptionId $targetSubscription.Id
                        
                        if ($containers -and $containers.Count -gt 0) {
                            Write-Host "`nContenedores disponibles:" -ForegroundColor Cyan
                            for ($i = 0; $i -lt $containers.Count; $i++) {
                                Write-Host "$($i + 1). $($containers[$i].Name)" -ForegroundColor Yellow
                            }
                            Write-Host "$($containers.Count + 1). Especificar manualmente" -ForegroundColor Yellow
                            
                            do {
                                $containerSelection = Read-Host "`nSelecciona un contenedor (1-$($containers.Count + 1))"
                                $containerIndex = [int]$containerSelection - 1
                            } while ($containerIndex -lt 0 -or $containerIndex -gt $containers.Count)
                            
                            if ($containerIndex -eq $containers.Count) {
                                $containerName = Read-Host "Especifica el nombre del contenedor"
                            } else {
                                $containerName = $containers[$containerIndex].Name
                            }
                        } else {
                            $containerName = Read-Host "No se pudieron listar los contenedores. Especifica el nombre del contenedor"
                        }
                    } else {
                        $containerName = Read-Host "Especifica el nombre del contenedor"
                    }
                    
                    $targetScope = "/subscriptions/$($targetSubscription.Id)/resourceGroups/$targetRgName/providers/Microsoft.Storage/storageAccounts/$targetResourceName/blobServices/default/containers/$containerName"
                    Write-Host "Ámbito: Contenedor '$containerName' en Storage Account '$targetResourceName'" -ForegroundColor White
                } else {
                    $targetScope = "/subscriptions/$($targetSubscription.Id)/resourceGroups/$targetRgName/providers/$targetResourceType/$targetResourceName"
                    Write-Host "Ámbito: Storage Account completo '$targetResourceName'" -ForegroundColor White
                }
            }
            # Configuración específica para Virtual Network
            elseif ($targetResourceType -eq "Microsoft.Network/virtualNetworks") {
                Write-Host "`n--- CONFIGURACIÓN DE VIRTUAL NETWORK ---" -ForegroundColor Cyan
                $subnetChoice = Read-Host "¿Desea operar a nivel de subnet específica? (y/N)"
                
                if ($subnetChoice -eq "y" -or $subnetChoice -eq "Y") {
                    if (-not $isRemovalOperation) {
                        Write-Host "`nObteniendo subnets disponibles..." -ForegroundColor Yellow
                        $subnets = Get-VirtualNetworkSubnets -VNetName $targetResourceName -ResourceGroupName $targetRgName -SubscriptionId $targetSubscription.Id
                        
                        if ($subnets -and $subnets.Count -gt 0) {
                            Write-Host "`nSubnets disponibles:" -ForegroundColor Cyan
                            for ($i = 0; $i -lt $subnets.Count; $i++) {
                                Write-Host "$($i + 1). $($subnets[$i].Name) - $($subnets[$i].AddressPrefix)" -ForegroundColor Yellow
                            }
                            Write-Host "$($subnets.Count + 1). Especificar manualmente" -ForegroundColor Yellow
                            
                            do {
                                $subnetSelection = Read-Host "`nSelecciona una subnet (1-$($subnets.Count + 1))"
                                $subnetIndex = [int]$subnetSelection - 1
                            } while ($subnetIndex -lt 0 -or $subnetIndex -gt $subnets.Count)
                            
                            if ($subnetIndex -eq $subnets.Count) {
                                $subnetName = Read-Host "Especifica el nombre de la subnet"
                            } else {
                                $subnetName = $subnets[$subnetIndex].Name
                            }
                        } else {
                            $subnetName = Read-Host "No se pudieron listar las subnets. Especifica el nombre de la subnet"
                        }
                    } else {
                        $subnetName = Read-Host "Especifica el nombre de la subnet"
                    }
                    
                    $targetScope = "/subscriptions/$($targetSubscription.Id)/resourceGroups/$targetRgName/providers/Microsoft.Network/virtualNetworks/$targetResourceName/subnets/$subnetName"
                    Write-Host "Ámbito: Subnet '$subnetName' en Virtual Network '$targetResourceName'" -ForegroundColor White
                } else {
                    $targetScope = "/subscriptions/$($targetSubscription.Id)/resourceGroups/$targetRgName/providers/$targetResourceType/$targetResourceName"
                    Write-Host "Ámbito: Virtual Network completa '$targetResourceName'" -ForegroundColor White
                }
            }
            # Configuración para otros tipos de recursos
            else {
                $targetScope = "/subscriptions/$($targetSubscription.Id)/resourceGroups/$targetRgName/providers/$targetResourceType/$targetResourceName"
                Write-Host "Ámbito: Recurso específico '$targetResourceName'" -ForegroundColor White
            }
        }
    }

    # 4. Configuración del rol
    if ($isRemovalOperation) {
        # Para eliminación, mostrar asignaciones existentes en el scope específico
        Write-Host "`n--- SELECCIÓN DE ROL A ELIMINAR ---" -ForegroundColor Cyan
        $assignmentToRemove = Get-ExistingRoleAssignments -ManagedIdentityId $managedIdentityId -TargetScope $targetScope
        if (-not $assignmentToRemove) {
            return
        }
        $roleName = $assignmentToRemove.RoleDefinitionName
    } else {
        # Para asignación, mostrar roles comunes
        Write-Host "`n--- CONFIGURACIÓN DEL ROL ---" -ForegroundColor Cyan

        $commonRoles = @(
            "Storage Blob Data Reader",
            "Storage Blob Data Contributor",
            "Storage Blob Data Owner",
            "Key Vault Reader",
            "Key Vault Secrets User",
            "Key Vault Secrets Officer",
            "Reader",
            "Data Factory Contributor",
            "Network Contributor",
            "Virtual Machine Contributor",
            "Monitoring Reader",
            "Log Analytics Reader",
            "Otro (especificar manualmente)"
        )

        $selectedRole = Show-Menu -Title "Rol a asignar" -Options $commonRoles

        if ($selectedRole -eq "Otro (especificar manualmente)") {
            $roleName = Read-Host "Especifica el nombre exacto del rol"
        } else {
            $roleName = $selectedRole
        }

        # Validar roles restringidos (solo para asignación)
        try {
            Test-RestrictedRole -RoleName $roleName
            Write-Host "✅ Validación de rol exitosa" -ForegroundColor Green
        }
        catch {
            Write-Error $_.Exception.Message
            return
        }
    }

    # 5. Verificar asignaciones existentes (solo para asignación)
    if (-not $isRemovalOperation) {
        Write-Host "`nVerificando asignaciones existentes..." -ForegroundColor Yellow

        try {
            $existingAssignments = Get-AzRoleAssignment -ObjectId $managedIdentityId -Scope $targetScope -ErrorAction SilentlyContinue
            $existingRole = $existingAssignments | Where-Object { $_.RoleDefinitionName -eq $roleName }

            if ($existingRole) {
                Write-Warning "La Managed Identity ya tiene el rol '$roleName' asignado en este ámbito."
                $continue = Read-Host "¿Continuar de todas formas? (y/N)"
                if ($continue -ne "y" -and $continue -ne "Y") {
                    Write-Host "Operación cancelada." -ForegroundColor Yellow
                    return
                }
            }
        } catch {
            Write-Host "No se pudieron verificar asignaciones existentes. Continuando..." -ForegroundColor Yellow
        }
    }

    # 6. Mostrar resumen
    if ($isRemovalOperation) {
        Write-Host "`n=== RESUMEN DE ELIMINACIÓN ===" -ForegroundColor Magenta
        Write-Host "🗑️  OPERACIÓN: ELIMINAR ROL" -ForegroundColor Red
    } else {
        Write-Host "`n=== RESUMEN DE ASIGNACIÓN ===" -ForegroundColor Magenta
        Write-Host "➕ OPERACIÓN: ASIGNAR ROL" -ForegroundColor Green
    }
    
    Write-Host "Recurso Origen: $sourceResourceName ($sourceResourceType)" -ForegroundColor White
    Write-Host "Ambiente Origen: $sourceEnvironment" -ForegroundColor White
    Write-Host "Managed Identity ID: $managedIdentityId" -ForegroundColor White
    Write-Host "Rol: $roleName" -ForegroundColor White
    Write-Host "Ámbito: $selectedScope" -ForegroundColor White
    if ($targetResourceName) {
        Write-Host "Recurso Destino: $targetResourceName" -ForegroundColor White
        Write-Host "Ambiente Destino: $targetEnvironment" -ForegroundColor White
    }
    Write-Host "Scope Path: $targetScope" -ForegroundColor White

    if ($isRemovalOperation) {
        $confirm = Read-Host "`n¿Proceder con la ELIMINACIÓN? (y/N)"
    } else {
        $confirm = Read-Host "`n¿Proceder con la ASIGNACIÓN? (y/N)"
    }
    
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Host "Operación cancelada." -ForegroundColor Yellow
        return
    }

    # 7. Ejecutar la operación
    if ($isRemovalOperation) {
        Write-Host "`nEliminando asignación de rol..." -ForegroundColor Yellow
        try {
            Remove-AzRoleAssignment -ObjectId $managedIdentityId -RoleDefinitionName $roleName -Scope $targetScope -ErrorAction Stop
            
            Write-Host "`n✅ ¡Asignación eliminada exitosamente!" -ForegroundColor Green
            
            if ($targetResourceName) {
                Write-Host "Se eliminó el rol '$roleName' de la Managed Identity del recurso '$sourceResourceName' sobre '$targetResourceName'" -ForegroundColor Green
            } else {
                Write-Host "Se eliminó el rol '$roleName' de la Managed Identity del recurso '$sourceResourceName' en el Management Group" -ForegroundColor Green
            }
            
        } catch {
            Write-Error "Error al eliminar la asignación: $($_.Exception.Message)"
        }
    } else {
        Write-Host "`nEjecutando asignación de rol..." -ForegroundColor Yellow
        try {
            $assignment = New-AzRoleAssignment -ObjectId $managedIdentityId -RoleDefinitionName $roleName -Scope $targetScope

            Write-Host "`n✅ ¡Asignación completada exitosamente!" -ForegroundColor Green
            Write-Host "Assignment ID: $($assignment.RoleAssignmentId)" -ForegroundColor Cyan
            
            if ($targetResourceName) {
                Write-Host "La Managed Identity del recurso '$sourceResourceName' ahora tiene el rol '$roleName' sobre '$targetResourceName'" -ForegroundColor Green
            } else {
                Write-Host "La Managed Identity del recurso '$sourceResourceName' ahora tiene el rol '$roleName' en el Management Group" -ForegroundColor Green
            }

        } catch {
            Write-Error "Error al crear la asignación: $($_.Exception.Message)"

            if ($_.Exception.Message -like "*does not exist*") {
                Write-Host "`n💡 Sugerencias:" -ForegroundColor Yellow
                Write-Host "• Verifica que el nombre del rol sea exacto" -ForegroundColor Gray
                Write-Host "• Verifica que tengas permisos en el ámbito destino" -ForegroundColor Gray
                Write-Host "• Verifica que el recurso destino exista" -ForegroundColor Gray
            }
        }
    }
}

# Función para listar roles comunes para Managed Identities
function Get-CommonManagedIdentityRoles {
    Write-Host "`n=== ROLES COMUNES PARA MANAGED IDENTITIES ===" -ForegroundColor Cyan
    
    $commonRoles = @(
        @{Role="Storage Blob Data Reader"; Description="Lectura de blobs en Storage Account"},
        @{Role="Storage Blob Data Contributor"; Description="Lectura/escritura de blobs en Storage Account"},
        @{Role="Storage Blob Data Owner"; Description="Control total sobre blobs en Storage Account"},
        @{Role="Key Vault Reader"; Description="Lectura de metadatos de Key Vault"},
        @{Role="Key Vault Secrets User"; Description="Lectura de secretos de Key Vault"},
        @{Role="Key Vault Secrets Officer"; Description="Gestión de secretos de Key Vault"},
        @{Role="Data Factory Contributor"; Description="Gestión de Data Factory"},
        @{Role="Network Contributor"; Description="Gestión de recursos de red"},
        @{Role="Reader"; Description="Lectura de recursos"},
        @{Role="Monitoring Reader"; Description="Lectura de datos de monitoreo"},
        @{Role="Log Analytics Reader"; Description="Lectura de logs de Log Analytics"}
    )
    
    $commonRoles | ForEach-Object {
        Write-Host "• $($_.Role)" -ForegroundColor Yellow
        Write-Host "  $($_.Description)" -ForegroundColor Gray
    }
}

# Ejecutar la función principal
New-ManagedIdentityRoleManagement

Write-Host "`n💡 Tips:" -ForegroundColor Green
Write-Host "• Ejecuta 'Get-CommonManagedIdentityRoles' para ver roles comunes" -ForegroundColor Gray
Write-Host "• El ambiente se detecta automáticamente por la antepenúltima letra del nombre" -ForegroundColor Gray
Write-Host "• Para asignación: Solo se permite entre recursos del mismo ambiente" -ForegroundColor Gray
Write-Host "• Para eliminación: Se puede eliminar de cualquier ámbito" -ForegroundColor Gray
Write-Host "• Para Storage Accounts puedes operar a nivel de contenedor" -ForegroundColor Gray
Write-Host "• Para Virtual Networks puedes operar a nivel de subnet" -ForegroundColor Gray