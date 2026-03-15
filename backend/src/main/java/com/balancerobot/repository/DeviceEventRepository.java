package com.balancerobot.repository;

import com.balancerobot.entity.DeviceEvent;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;

public interface DeviceEventRepository extends JpaRepository<DeviceEvent, Long> {
    List<DeviceEvent> findByDeviceIdOrderByOccurredAtDesc(Long deviceId, Pageable pageable);
}
