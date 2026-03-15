package com.balancerobot.repository;

import com.balancerobot.entity.Device;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;
import java.util.Optional;

public interface DeviceRepository extends JpaRepository<Device, Long> {
    Optional<Device> findByDeviceId(String deviceId);

    Optional<Device> findByDeviceIdAndOwnerId(String deviceId, Long ownerId);

    List<Device> findByOwnerId(Long ownerId);

    boolean existsByDeviceId(String deviceId);
}
