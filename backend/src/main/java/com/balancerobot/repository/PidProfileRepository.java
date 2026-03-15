package com.balancerobot.repository;

import com.balancerobot.entity.PidProfile;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;
import java.util.Optional;

public interface PidProfileRepository extends JpaRepository<PidProfile, Long> {
    List<PidProfile> findByUserId(Long userId);

    Optional<PidProfile> findByUserIdAndDeviceIsNullAndIsActiveTrue(Long userId);

    Optional<PidProfile> findByUserIdAndDeviceIdAndIsActiveTrue(Long userId, Long deviceId);
}
